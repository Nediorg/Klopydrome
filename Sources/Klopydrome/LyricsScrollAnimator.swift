import SwiftUI
import AppKit

struct LyricsLineFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct LyricsScrollAnimator: NSViewRepresentable {
    @Binding var coordinator: LyricsScrollAnimator.Coordinator?
    var onUserScrollChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostedView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostedView = nsView
        context.coordinator.onUserScrollChange = onUserScrollChange
        context.coordinator.setupScrollObserversIfNeeded()
        if coordinator !== context.coordinator {
            Task { @MainActor in coordinator = context.coordinator }
        }
    }

    final class Coordinator: NSObject {
        weak var hostedView: NSView?
        var onUserScrollChange: ((Bool) -> Void)?
        var lineFrames: [Int: CGRect] = [:]

        private var displayLink: CADisplayLink?
        private var fallbackTimer: Timer?
        private var startOrigin = CGPoint.zero
        private var targetOrigin = CGPoint.zero
        private var startTime: CFTimeInterval = 0
        private var duration: TimeInterval = 0.4
        private var isObservingScroll = false

        var scrollView: NSScrollView? { hostedView?.enclosingScrollView }

        func setupScrollObserversIfNeeded() {
            guard !isObservingScroll, let scrollV = scrollView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleLiveScrollStart(_:)),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollV
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleLiveScrollEnd(_:)),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollV
            )
            isObservingScroll = true
        }

        @objc private func handleLiveScrollStart(_ notification: Notification) {
            onUserScrollChange?(true)
        }

        @objc private func handleLiveScrollEnd(_ notification: Notification) {
            onUserScrollChange?(false)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            stopDrivers()
        }

        func animate(to offsetY: CGFloat, duration: TimeInterval) {
            guard let scrollView else { return }
            let flipped = scrollView.documentView?.isFlipped ?? true
            let clip = scrollView.contentView
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            let targetY = min(max(0, offsetY), maxY)
            let target = NSPoint(x: 0, y: flipped ? targetY : -targetY)
            let current = clip.bounds.origin
            guard abs(target.y - current.y) > 0.5 else { return }

            startOrigin = current
            targetOrigin = target
            startTime = 0
            self.duration = duration

            stopDrivers()
            let fallback = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.driveFrame(at: CACurrentMediaTime())
            }
            RunLoop.main.add(fallback, forMode: .common)
            fallbackTimer = fallback
            if let hostedView {
                let link = hostedView.displayLink(target: self, selector: #selector(glideStep(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        @objc private func glideStep(_ link: CADisplayLink) {
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            driveFrame(at: CACurrentMediaTime())
        }

        private func driveFrame(at now: CFTimeInterval) {
            guard let scrollView else {
                stopDrivers()
                return
            }
            if startTime == 0 { startTime = now }
            let elapsed = now - startTime
            let progress = min(max(elapsed / duration, 0), 1)
            let eased = Self.easeOutCubic(progress)
            let origin = CGPoint(
                x: startOrigin.x + (targetOrigin.x - startOrigin.x) * eased,
                y: startOrigin.y + (targetOrigin.y - startOrigin.y) * eased
            )
            scrollView.contentView.setBoundsOrigin(origin)
            if progress >= 1 {
                stopDrivers()
            }
        }

        private func stopDrivers() {
            displayLink?.invalidate()
            displayLink = nil
            fallbackTimer?.invalidate()
            fallbackTimer = nil
        }

        private static func easeOutCubic(_ progress: Double) -> Double {
            1.0 - pow(1.0 - progress, 3)
        }
    }
}
