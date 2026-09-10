import SwiftUI
import AppKit

/// Preference carrying each lyric line's frame in the scroll content's own
/// coordinate space. Content space is stable while scrolling (it is the
/// document's space, not the viewport's), so the measured frames stay valid
/// for the whole song.
struct LyricsLineFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Invisible zero-size view placed inside the lyrics `ScrollView`'s content.
/// Its coordinator grabs the backing `NSScrollView` via `enclosingScrollView`
/// and drives the follow glide by writing the clip bounds every tick.
/// SwiftUI's own programmatic scroll paths — `scrollTo`, writes to a
/// `scrollPosition` binding, even `.animation(value:)` on the binding — all
/// squash the animation to a fixed fast (~100ms) scroll animation regardless
/// of the requested animation, which reads as a snap. `NSAnimationContext` +
/// `animator()` gets the duration right but runs on AppKit's timer (~30Hz),
/// which reads as a stuttery glide. Writing each eased position per tick
/// directly is the way to get a genuinely smooth, duration-controlled glide.
///
/// Two drivers race to own the glide: a `CADisplayLink` (macOS 14+,
/// `NSView.displayLink`) ticks at the display's refresh rate — vsync-smooth in
/// the running app — while a 1/60s fallback timer covers contexts where the
/// link never fires (headless tests, occluded windows). Whichever ticks first
/// cancels the other.
struct LyricsScrollAnimator: NSViewRepresentable {
    @Binding var coordinator: LyricsScrollAnimator.Coordinator?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostedView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostedView = nsView
        if coordinator !== context.coordinator {
            Task { @MainActor in coordinator = context.coordinator }
        }
    }

    final class Coordinator: NSObject {
        /// The zero-size view hosted inside the scroll content; its superview
        /// chain reaches the SwiftUI scroll view's backing `NSScrollView`.
        weak var hostedView: NSView?

        private var displayLink: CADisplayLink?
        private var fallbackTimer: Timer?
        private var startOrigin = CGPoint.zero
        private var targetOrigin = CGPoint.zero
        private var startTime: CFTimeInterval = 0
        private var duration: TimeInterval = 0.4

        var scrollView: NSScrollView? { hostedView?.enclosingScrollView }

        /// Glide the viewport so content offset `offsetY` (in flipped content
        /// coordinates) is at the top of the clip, over `duration`.
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
            startTime = CACurrentMediaTime()
            self.duration = duration

            stopDrivers()
            let fallback = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.driveFrame(at: CACurrentMediaTime())
            }
            RunLoop.main.add(fallback, forMode: .common)
            fallbackTimer = fallback
            if let hostedView {
                displayLink = hostedView.displayLink(target: self, selector: #selector(glideStep(_:)))
            }
        }

        @objc private func glideStep(_ link: CADisplayLink) {
            // The display link answered first: it owns the glide, drop the
            // fallback timer.
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            driveFrame(at: link.timestamp)
        }

        private func driveFrame(at now: CFTimeInterval) {
            guard let scrollView else {
                stopDrivers()
                return
            }
            let elapsed = now - startTime
            let progress = min(max(elapsed / duration, 0), 1)
            let eased = Self.easeInOutCubic(progress)
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

        private static func easeInOutCubic(_ progress: Double) -> Double {
            progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
        }
    }
}
