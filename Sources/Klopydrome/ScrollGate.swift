import AppKit
import Foundation

/// Monitors scroll events globally in the app to suppress expensive hover re-renders
/// while the user is actively scrolling through long lists.
/// When scrolling stops, hover is instantly re-enabled.
@MainActor
final class ScrollGate {
    static let shared = ScrollGate()

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
        // Ignore zero-delta events that some trackpads send
        if event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0 && event.deltaX == 0 && event.deltaY == 0 {
            return
        }

        isScrolling = true
        resetTask?.cancel()

        let delayNanos: UInt64
        if event.phase == .ended || event.momentumPhase == .ended {
            delayNanos = 40_000_000 // 40ms quick reset when gesture explicitly ends
        } else {
            delayNanos = 100_000_000 // 100ms debounce while wheel/momentum ticks continue
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

/// Reference-type tracker for cursor presence, avoiding SwiftUI view invalidation
/// during raw mouse enter/exit events while scrolling is active.
final class HoverTracker {
    var isInside = false
}
