import XCTest
@testable import Klopydrome

final class AutomixTransitionAnalysisTests: XCTestCase {
    private func profile(
        leading: [Float] = [],
        trailing: [Float] = [],
        frameDuration: Double = 0.1
    ) -> AutomixEdgeProfile {
        AutomixEdgeProfile(
            frameDuration: frameDuration,
            leadingDBFS: leading,
            trailingDBFS: trailing
        )
    }

    func testSilenceDefinesFadeDurationAndIncomingLeadIn() {
        let outgoing = profile(trailing: Array(repeating: -12, count: 80) + Array(repeating: -52, count: 40))
        let incoming = profile(leading: Array(repeating: -52, count: 30) + Array(repeating: -12, count: 90))

        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: outgoing,
            incoming: incoming
        )

        XCTAssertEqual(plan.basis, .silence)
        XCTAssertEqual(plan.fadeDuration, 4, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 196, accuracy: 0.001)
        XCTAssertEqual(plan.incomingLeadIn, 3, accuracy: 0.001)
    }

    func testOnsetRefinesFallbackWhenNoSilenceExists() {
        var tail = Array(repeating: Float(-20), count: 120)
        tail[68] = -30
        tail[69] = -1
        tail[70] = -30
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: profile(trailing: tail),
            incoming: profile(leading: Array(repeating: -20, count: 120))
        )

        XCTAssertEqual(plan.basis, .onset)
        XCTAssertGreaterThanOrEqual(plan.fadeDuration, AutomixTransitionPlanner.minimumFade)
        XCTAssertLessThanOrEqual(plan.fadeDuration, AutomixTransitionPlanner.maximumFade)
    }

    func testFallbackIsSafeWithoutDecodedProfiles() {
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: nil,
            incoming: nil
        )

        XCTAssertEqual(plan.basis, .fallback)
        XCTAssertEqual(plan.fadeDuration, AutomixTransitionPlanner.defaultFade, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 195, accuracy: 0.001)
    }
    func testPreferredFadeDurationOverridesFallback() {
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: nil,
            incoming: nil,
            preferredFadeDuration: 9
        )

        XCTAssertEqual(plan.basis, .fallback)
        XCTAssertEqual(plan.fadeDuration, 9, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 191, accuracy: 0.001)
    }
}
