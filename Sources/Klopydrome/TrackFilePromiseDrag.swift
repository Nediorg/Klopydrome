import AppKit
import Foundation
import NavidromeClient
import SwiftUI
import UniformTypeIdentifiers

final class TrackFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private static let workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "app.klopydrome.drag-file-promise"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private let payload: TrackDragPayload
    private let suggestedFilename: String
    private let exporter: TrackFileExporter

    init(payload: TrackDragPayload, suggestedFilename: String, exporter: TrackFileExporter = .shared) {
        self.payload = payload
        self.suggestedFilename = suggestedFilename
        self.exporter = exporter
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        suggestedFilename
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.workQueue
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let payload = self.payload
        let exporter = self.exporter
        Task.detached(priority: .userInitiated) {
            do {
                try await exporter.downloadTrack(for: payload, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

final class TrackFilePromiseProvider: NSFilePromiseProvider {
    private static let internalType = NSPasteboard.PasteboardType(UTType.trackDragPayload.identifier)

    private var internalPayloadData: Data?
    private var retainedDelegate: TrackFilePromiseDelegate?

    override init() {
        super.init()
    }

    convenience init(payload: TrackDragPayload, suggestedFilename: String, exporter: TrackFileExporter = .shared) {
        self.init()
        let ext = URL(fileURLWithPath: suggestedFilename).pathExtension
        let promiseDelegate = TrackFilePromiseDelegate(
            payload: payload,
            suggestedFilename: suggestedFilename,
            exporter: exporter
        )
        self.retainedDelegate = promiseDelegate
        self.internalPayloadData = try? JSONEncoder().encode(payload)
        self.fileType = UTType(filenameExtension: ext)?.identifier ?? UTType.audio.identifier
        self.delegate = promiseDelegate
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if internalPayloadData != nil {
            types.insert(Self.internalType, at: 0)
        }
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == Self.internalType {
            return internalPayloadData
        }
        return super.pasteboardPropertyList(forType: type)
    }
}

@MainActor
final class TrackDragCoordinator: NSObject, NSDraggingSource {
    static let shared = TrackDragCoordinator()

    private var anchors = NSHashTable<TrackDragAnchorView>.weakObjects()
    private var monitor: Any?
    private var pending: (anchor: TrackDragAnchorView, downEvent: NSEvent, startPoint: NSPoint)?

    func register(_ anchor: TrackDragAnchorView) {
        anchors.add(anchor)
        installMonitorIfNeeded()
    }

    func unregister(_ anchor: TrackDragAnchorView) {
        anchors.remove(anchor)
        if pending?.anchor === anchor {
            pending = nil
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            handleMouseDown(event)
            return event
        case .leftMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp:
            pending = nil
            return event
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        pending = nil
        guard let window = event.window else { return }
        if let hit = window.contentView?.hitTest(event.locationInWindow),
           hit is NSButton || hit is NSTextField || hit is NSSlider || hit is NSSegmentedControl {
            return
        }
        guard let anchor = findAnchor(at: event.locationInWindow, in: window) else { return }
        pending = (anchor, event, event.locationInWindow)
    }

    private func handleMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard let state = pending else { return event }
        let dx = event.locationInWindow.x - state.startPoint.x
        let dy = event.locationInWindow.y - state.startPoint.y
        guard hypot(dx, dy) >= 5 else { return event }

        pending = nil
        startDrag(from: state.anchor, downEvent: state.downEvent)
        return nil
    }

    private func findAnchor(at windowPoint: NSPoint, in window: NSWindow) -> TrackDragAnchorView? {
        var best: TrackDragAnchorView?
        for anchor in anchors.allObjects {
            guard anchor.window === window,
                  anchor.isDragEnabled,
                  !anchor.isHiddenOrHasHiddenAncestor else { continue }
            let local = anchor.convert(windowPoint, from: nil)
            if anchor.bounds.contains(local) {
                best = anchor
            }
        }
        return best
    }

    private func startDrag(from anchor: TrackDragAnchorView, downEvent: NSEvent) {
        guard let payload = anchor.makePayload?() else { return }
        let writer: any NSPasteboardWriting
        if payload.canExportSingleFile,
           let songID = payload.singleSongID,
           let info = payload.exportInfo {
            if let cachedURL = TrackFileExporter.shared.localCachedURL(for: songID, info: info) {
                let item = NSPasteboardItem()
                if let data = try? JSONEncoder().encode(payload) {
                    item.setData(data, forType: NSPasteboard.PasteboardType(UTType.trackDragPayload.identifier))
                }
                item.setString(cachedURL.absoluteString, forType: .fileURL)
                item.setPropertyList([cachedURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
                writer = item
            } else {
                writer = TrackFilePromiseProvider(payload: payload, suggestedFilename: info.suggestedFilename)
            }
        } else {
            let item = NSPasteboardItem()
            if let data = try? JSONEncoder().encode(payload) {
                item.setData(data, forType: NSPasteboard.PasteboardType(UTType.trackDragPayload.identifier))
            }
            writer = item
        }

        let label = anchor.makeLabel?() ?? payload.exportInfo?.suggestedFilename ?? ""
        let image = Self.makeDragPillImage(title: label)
        let localPoint = anchor.convert(downEvent.locationInWindow, from: nil)
        let frame = NSRect(
            x: localPoint.x - image.size.width / 2,
            y: localPoint.y - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(frame, contents: image)
        anchor.beginDraggingSession(with: [draggingItem], event: downEvent, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : .copy
    }

    private static func makeDragPillImage(title: String) -> NSImage {
        let display = title.isEmpty ? "Track" : title
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textWidth = min(220, ceil((display as NSString).size(withAttributes: attrs).width))
        let size = NSSize(width: max(84, textWidth + 36), height: 28)

        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()

            let icon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            icon?.draw(in: NSRect(x: 10, y: 7, width: 14, height: 14))

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            var drawAttrs = attrs
            drawAttrs[.paragraphStyle] = paragraph
            let textRect = NSRect(x: 28, y: 6, width: rect.width - 38, height: 16)
            (display as NSString).draw(in: textRect, withAttributes: drawAttrs)
            return true
        }
    }
}

final class TrackDragAnchorView: NSView {
    var isDragEnabled = true
    var makePayload: (() -> TrackDragPayload)?
    var makeLabel: (() -> String)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            TrackDragCoordinator.shared.register(self)
        } else {
            TrackDragCoordinator.shared.unregister(self)
        }
    }
}

private struct TrackDragAnchorRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let makeLabel: () -> String
    let makePayload: () -> TrackDragPayload

    func makeNSView(context: Context) -> TrackDragAnchorView {
        let view = TrackDragAnchorView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: TrackDragAnchorView, context: Context) {
        nsView.isDragEnabled = isEnabled
        nsView.makeLabel = makeLabel
        nsView.makePayload = makePayload
    }
}

extension View {
    func trackDraggable(
        isEnabled: Bool = true,
        label: @escaping () -> String,
        payload: @escaping () -> TrackDragPayload
    ) -> some View {
        background(
            TrackDragAnchorRepresentable(
                isEnabled: isEnabled,
                makeLabel: label,
                makePayload: payload
            )
        )
    }
}
