import AppKit
import NavidromeClient
import SwiftUI

/// Per-row hover state so only the specific row under the cursor invalidates.
@Observable
final class RowHoverState {
    var isHovered: Bool = false
}

/// Coordinates native AppKit hover tracking and routes hover state to individual rows.
@MainActor
final class RowHoverManager {
    private var states: [SubsonicSong.ID: RowHoverState] = [:]
    private var currentHoveredID: SubsonicSong.ID?

    func state(for id: SubsonicSong.ID) -> RowHoverState {
        if let existing = states[id] {
            return existing
        }
        let state = RowHoverState()
        states[id] = state
        return state
    }

    func setHovered(id: SubsonicSong.ID?) {
        guard currentHoveredID != id else { return }
        if let prev = currentHoveredID, let state = states[prev] {
            state.isHovered = false
        }
        currentHoveredID = id
        if let next = id, let state = states[next] {
            state.isHovered = true
        }
    }

    func clearHover() {
        setHovered(id: nil)
    }
}

/// Backing NSTableView configuration: full-width rows, row height, and native
/// AppKit mouse tracking for instantaneous row-accurate hover across the entire row height
/// without per-cell SwiftUI overhead.
struct TableTweaks: NSViewRepresentable {
    let songCount: Int
    let hoverManager: RowHoverManager
    var rowHeight: CGFloat = 22
    var onPrefetch: (() -> Void)?
    var songIDAtRow: ((Int) -> SubsonicSong.ID?)?

    func makeCoordinator() -> Coordinator {
        Coordinator(hoverManager: hoverManager)
    }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.songCount = songCount
        context.coordinator.rowHeight = rowHeight
        context.coordinator.onPrefetch = onPrefetch
        context.coordinator.songIDAtRow = songIDAtRow

        guard !context.coordinator.isAttached else { return }

        let applyTweaks = {
            var root: NSView? = view
            while let currentRoot = root, Self.table(in: currentRoot) == nil { root = currentRoot.superview }
            guard let tableView = root.flatMap({ Self.table(in: $0) }) else { return false }
            context.coordinator.attach(to: tableView)
            if tableView.style != .inset { tableView.style = .inset }
            if tableView.rowHeight != rowHeight { tableView.rowHeight = rowHeight }
            return true
        }

        if !applyTweaks() {
            DispatchQueue.main.async {
                _ = applyTweaks()
            }
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews { if let table = table(in: subview) { return table } }
        return nil
    }

    @MainActor
    final class Coordinator: NSResponder {
        var songCount: Int = 0
        var rowHeight: CGFloat = 22
        var onPrefetch: (() -> Void)?
        var songIDAtRow: ((Int) -> SubsonicSong.ID?)?
        let hoverManager: RowHoverManager
        var isAttached: Bool { tableView != nil }

        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private var trackingArea: NSTrackingArea?
        private var scrollStartObserver: Any?
        private var scrollEndObserver: Any?
        private var clipViewBoundsObserver: Any?
        private var scrollDebounceWorkItem: DispatchWorkItem?
        private var isTableScrolling = false

        init(hoverManager: RowHoverManager) {
            self.hoverManager = hoverManager
            super.init()

            scrollStartObserver = NotificationCenter.default.addObserver(
                forName: ScrollGate.scrollDidStart,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleScrollDidStart()
            }

            scrollEndObserver = NotificationCenter.default.addObserver(
                forName: ScrollGate.scrollDidEnd,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleScrollDidEnd()
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            scrollDebounceWorkItem?.cancel()
            if let scrollStartObserver {
                NotificationCenter.default.removeObserver(scrollStartObserver)
            }
            if let scrollEndObserver {
                NotificationCenter.default.removeObserver(scrollEndObserver)
            }
            if let clipViewBoundsObserver {
                NotificationCenter.default.removeObserver(clipViewBoundsObserver)
            }
        }

        func attach(to tableView: NSTableView) {
            if let window = tableView.window {
                window.acceptsMouseMovedEvents = true
            }
            guard self.tableView !== tableView else { return }
            detach()
            self.tableView = tableView

            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            tableView.addTrackingArea(area)
            self.trackingArea = area

            if let clip = tableView.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                clipView = clip
                clipViewBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clip,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleClipViewBoundsDidChange()
                }
            }
        }

        func detach() {
            scrollDebounceWorkItem?.cancel()
            scrollDebounceWorkItem = nil
            if let trackingArea, let tableView {
                tableView.removeTrackingArea(trackingArea)
            }
            trackingArea = nil
            tableView = nil
            if let clipViewBoundsObserver {
                NotificationCenter.default.removeObserver(clipViewBoundsObserver)
                self.clipViewBoundsObserver = nil
            }
            clipView = nil
        }

        override func mouseMoved(with event: NSEvent) {
            guard let tableView else { return }
            if let window = event.window {
                window.acceptsMouseMovedEvents = true
            }
            guard !isTableScrolling, !ScrollGate.shared.isScrolling else {
                hoverManager.clearHover()
                return
            }
            let point = tableView.convert(event.locationInWindow, from: nil)
            updateHover(at: point)
        }

        override func mouseEntered(with event: NSEvent) {
            mouseMoved(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            hoverManager.clearHover()
        }

        private func updateHover(at point: NSPoint) {
            guard let tableView else { return }
            let row = tableView.row(at: point)
            let newId = (row >= 0 && row < songCount) ? songIDAtRow?(row) : nil
            hoverManager.setHovered(id: newId)
        }

        private func handleClipViewBoundsDidChange() {
            isTableScrolling = true
            hoverManager.clearHover()
            if let tableView, let clipView {
                let visible = tableView.rows(in: clipView.bounds)
                let maxVisible = visible.location + visible.length
                if maxVisible >= songCount - 150 {
                    onPrefetch?()
                }
            }
            scrollDebounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isTableScrolling = false
                self.handleScrollDidEnd()
            }
            scrollDebounceWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: item)
        }

        private func handleScrollDidStart() {
            isTableScrolling = true
            scrollDebounceWorkItem?.cancel()
            hoverManager.clearHover()
        }

        private func handleScrollDidEnd() {
            guard !isTableScrolling, !ScrollGate.shared.isScrolling else { return }
            guard let tableView, let window = tableView.window else { return }
            let mouseLoc = window.mouseLocationOutsideOfEventStream
            let point = tableView.convert(mouseLoc, from: nil)
            guard tableView.bounds.contains(point) else {
                hoverManager.clearHover()
                return
            }
            updateHover(at: point)
        }
    }
}
