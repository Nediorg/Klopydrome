import AppKit
import NavidromeClient
import SwiftUI

/// Which row the pointer is over. A reference type on purpose: only the cells
/// that *read* `id` (the ★ cells) are invalidated when it changes.
@Observable
final class RowHover {
    var id: SubsonicSong.ID?
}

/// Backing NSTableView configuration: full-width rows, row height, and native
/// AppKit mouse tracking for instantaneous row-accurate hover across the entire row height
/// without per-cell SwiftUI overhead.
struct TableTweaks: NSViewRepresentable {
    let displayedSongs: [SubsonicSong]
    let hover: RowHover
    var rowHeight: CGFloat = 22
    var onPrefetch: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(hover: hover)
    }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.displayedSongs = displayedSongs
        context.coordinator.rowHeight = rowHeight
        context.coordinator.onPrefetch = onPrefetch

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
        var displayedSongs: [SubsonicSong] = []
        var rowHeight: CGFloat = 22
        var onPrefetch: (() -> Void)?
        let hover: RowHover
        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private var trackingArea: NSTrackingArea?
        private var scrollStartObserver: Any?
        private var scrollEndObserver: Any?
        private var clipViewBoundsObserver: Any?
        private var scrollDebounceTask: Task<Void, Never>?
        private var isTableScrolling = false

        init(hover: RowHover) {
            self.hover = hover
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
            scrollDebounceTask?.cancel()
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
            scrollDebounceTask?.cancel()
            scrollDebounceTask = nil
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
                if hover.id != nil { hover.id = nil }
                return
            }
            let point = tableView.convert(event.locationInWindow, from: nil)
            updateHover(at: point)
        }

        override func mouseEntered(with event: NSEvent) {
            mouseMoved(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            if hover.id != nil {
                hover.id = nil
            }
        }

        private func updateHover(at point: NSPoint) {
            guard let tableView else { return }
            let row = tableView.row(at: point)
            let newId = (row >= 0 && row < displayedSongs.count) ? displayedSongs[row].id : nil
            if hover.id != newId {
                hover.id = newId
            }
        }

        private func handleClipViewBoundsDidChange() {
            isTableScrolling = true
            if hover.id != nil {
                hover.id = nil
            }
            if let tableView, let clipView {
                let visible = tableView.rows(in: clipView.bounds)
                let maxVisible = visible.location + visible.length
                if maxVisible >= displayedSongs.count - 150 {
                    onPrefetch?()
                }
            }
            scrollDebounceTask?.cancel()
            scrollDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.isTableScrolling = false
                self.handleScrollDidEnd()
            }
        }

        private func handleScrollDidStart() {
            isTableScrolling = true
            scrollDebounceTask?.cancel()
            if hover.id != nil {
                hover.id = nil
            }
        }

        private func handleScrollDidEnd() {
            guard !isTableScrolling, !ScrollGate.shared.isScrolling else { return }
            guard let tableView, let window = tableView.window else { return }
            let mouseLoc = window.mouseLocationOutsideOfEventStream
            let point = tableView.convert(mouseLoc, from: nil)
            guard tableView.bounds.contains(point) else {
                if hover.id != nil { hover.id = nil }
                return
            }
            updateHover(at: point)
        }
    }
}
