import AppKit
import Foundation

@MainActor
final class ScrollGate {
    static let shared = ScrollGate()

    static let scrollDidStart = Notification.Name("ScrollGateDidStart")
    static let scrollDidEnd = Notification.Name("ScrollGateDidEnd")

    private(set) var isScrolling = false
    private var resetTask: Task<Void, Never>?
    private var monitorToken: Any?

    private init() {
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.recordScroll(event)
            return event
        }
    }

    deinit {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
        }
    }

    private func recordScroll(_ event: NSEvent) {
        if event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0 && event.deltaX == 0 && event.deltaY == 0 {
            return
        }

        let wasScrolling = isScrolling
        isScrolling = true
        if !wasScrolling {
            NotificationCenter.default.post(name: Self.scrollDidStart, object: nil)
        }
        resetTask?.cancel()

        let delayNanos: UInt64
        if event.phase == .ended || event.momentumPhase == .ended {
            delayNanos = 40_000_000
        } else {
            delayNanos = 100_000_000
        }

        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.isScrolling = false
            NotificationCenter.default.post(name: Self.scrollDidEnd, object: nil)
        }
    }
}

final class HoverTracker {
    var isInside = false
}
