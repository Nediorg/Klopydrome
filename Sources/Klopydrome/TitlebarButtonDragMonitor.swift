import AppKit

/// Monitors mouse events on the window titlebar to enable dragging the window
/// by its buttons (transport controls, lyrics/queue buttons, etc.) when the mouse
/// is dragged beyond a minimum distance threshold, while canceling the button click.
@MainActor
final class TitlebarButtonDragMonitor {
    private static var monitors: [ObjectIdentifier: TitlebarButtonDragMonitor] = [:]

    static func install(on window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        monitors[identifier]?.stop()
        monitors[identifier] = TitlebarButtonDragMonitor(window: window)
    }

    private weak var window: NSWindow?
    private var monitorToken: Any?
    private var pendingDownEvent: NSEvent?
    private var pendingStartPoint: NSPoint = .zero
    private var didDragWindow = false

    private let dragThreshold: CGFloat = 3.0
    private let titlebarHeight: CGFloat = 52.0

    init(window: NSWindow) {
        self.window = window
        self.monitorToken = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleEvent(event) ?? event
        }
    }

    func stop() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }

        switch event.type {
        case .leftMouseDown:
            return handleMouseDown(event, window: window)
        case .leftMouseDragged:
            return handleMouseDragged(event, window: window)
        case .leftMouseUp:
            return handleMouseUp(event)
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent, window: NSWindow) -> NSEvent? {
        didDragWindow = false
        let point = event.locationInWindow
        guard isInsideTitlebar(point, window: window) else {
            pendingDownEvent = nil
            return event
        }
        if isNonDraggableHit(at: point, window: window) {
            pendingDownEvent = nil
            return event
        }
        pendingDownEvent = event
        pendingStartPoint = point
        return event
    }

    private func handleMouseDragged(_ event: NSEvent, window: NSWindow) -> NSEvent? {
        guard let downEvent = pendingDownEvent,
              isInsideTitlebar(event.locationInWindow, window: window) else {
            return event
        }

        let point = event.locationInWindow
        let deltaX = point.x - pendingStartPoint.x
        let deltaY = point.y - pendingStartPoint.y
        let distance = hypot(deltaX, deltaY)

        guard distance >= dragThreshold else {
            return event
        }

        pendingDownEvent = nil
        didDragWindow = true
        cancelButtonHighlight(window: window, downEvent: downEvent)
        window.performDrag(with: downEvent)
        return nil
    }

    private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
        pendingDownEvent = nil
        if didDragWindow {
            didDragWindow = false
            return nil
        }
        return event
    }

    private func isInsideTitlebar(_ point: NSPoint, window: NSWindow) -> Bool {
        point.y >= window.frame.height - titlebarHeight
            && point.y <= window.frame.height
            && point.x >= 80
    }

    private func isNonDraggableHit(at point: NSPoint, window: NSWindow) -> Bool {
        guard let hit = window.contentView?.superview?.hitTest(point) else {
            return false
        }
        return !hit.mouseDownCanMoveWindow
    }

    private func cancelButtonHighlight(window: NSWindow, downEvent: NSEvent) {
        let cancelPoint = NSPoint(x: -10000, y: -10000)
        let cancelEvents: [NSEvent.EventType] = [.leftMouseDragged, .leftMouseUp]
        for eventType in cancelEvents {
            if let mouseEvent = NSEvent.mouseEvent(
                with: eventType,
                location: cancelPoint,
                modifierFlags: downEvent.modifierFlags,
                timestamp: downEvent.timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: downEvent.eventNumber,
                clickCount: 1,
                pressure: 0
            ) {
                window.sendEvent(mouseEvent)
            }
        }
    }
}
