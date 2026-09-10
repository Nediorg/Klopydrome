import XCTest
import AppKit
import SwiftUI
import NavidromeClient
@testable import Klopydrome

/// Headless proof that the lyrics follow glides with the REQUESTED duration.
/// SwiftUI's programmatic scroll paths — `scrollTo`, `scrollPosition` binding
/// writes, even `.animation(value:)` on the binding — all run a fixed fast
/// (~100ms) scroll animation regardless of the animation you pass, which reads
/// as a snap. The follow therefore animates the backing `NSScrollView` clip
/// bounds directly (`LyricsScrollAnimator`). This test hosts the real pattern
/// and samples the clip-bounds origin while the glide runs, asserting it
/// passes through intermediate positions over ~0.8s instead of teleporting.
@MainActor
final class LyricsFollowAnimationTests: XCTestCase {

    @Observable
    final class ProbeTrigger {
        var fire = false
    }

    /// Mirrors the LyricsView follow structure: scroll targets per line, frame
    /// measurement in content space, `scrollPosition` as the scroll detector,
    /// and the animator gliding the clip bounds.
    private struct ProbeView: View {
        let trigger: ProbeTrigger
        @State private var target: Int?
        @State private var coordinator: LyricsScrollAnimator.Coordinator?
        @State private var frames: [Int: CGRect] = [:]

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { lineIndex in
                        Text("Line \(lineIndex)")
                            .font(.system(size: 14))
                            .frame(height: 30)
                            .id(lineIndex)
                            .background(GeometryReader { geo in
                                Color.clear.preference(
                                    key: LyricsLineFrameKey.self,
                                    value: [lineIndex: geo.frame(in: .named("probe"))]
                                )
                            })
                    }
                }
                .coordinateSpace(name: "probe")
                .onPreferenceChange(LyricsLineFrameKey.self) { frames = $0 }
                .background(alignment: .top) {
                    LyricsScrollAnimator(coordinator: $coordinator)
                        .frame(width: 0, height: 0)
                }
            }
            .scrollPosition(id: $target, anchor: .center)
            .onChange(of: trigger.fire) { _, armed in
                guard armed, let animator = coordinator,
                      let scrollView = animator.scrollView,
                      let frame = frames[10] else { return }
                let viewport = scrollView.contentView.bounds.height
                animator.animate(to: max(0, frame.midY - viewport / 2), duration: LyricsView.followDuration)
            }
            .frame(width: 200, height: 300)
        }
    }

    func testFollowGlideRespectsRequestedDuration() throws {
        let trigger = ProbeTrigger()
        let window = NSWindow(
            contentRect: .init(x: 100, y: 100, width: 200, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: ProbeView(trigger: trigger))
        hosting.frame = .init(x: 0, y: 0, width: 200, height: 300)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        pump(milliseconds: 150)

        guard let scroll = findScrollView(in: hosting) else {
            return XCTFail("no NSScrollView backing the SwiftUI ScrollView")
        }

        let start = scroll.contentView.bounds.origin.y
        trigger.fire = true
        pump(milliseconds: 50)

        // Sample every 50ms over 1.4s — covers the whole 0.8s glide plus margin.
        var distances: [CGFloat] = []
        for sampleIndex in 0..<28 {
            distances.append(abs(scroll.contentView.bounds.origin.y - start))
            pump(milliseconds: 50)
        }

        let final = distances.last ?? 0
        // 20 lines x 30pt, viewport 300: centering line 10 lands ~165pt down.
        XCTAssertGreaterThan(final, 100, "follow must reach the target line")
        XCTAssertLessThan(final, 250, "follow must stop at the centered line")
        let gliding = distances.filter { $0 > 0 && $0 < final }
        // 0.4s glide at 50ms sampling: ~6-7 growing samples; require at least 4
        // so the test tolerates run-loop jitter while still proving the glide.
        XCTAssertGreaterThanOrEqual(
            gliding.count, 4,
            "the glide must spend meaningful time between positions, not snap"
        )
        for (previous, next) in zip(distances, distances.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, previous - 2, "scroll offset must not oscillate")
        }
    }

    // MARK: Helpers

    private func pump(milliseconds: Int) {
        RunLoop.main.run(until: Date().addingTimeInterval(Double(milliseconds) / 1000))
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
