import Foundation
import XCTest
@testable import Klopydrome

final class MPVFailureFallbackTests: XCTestCase {
    func testArmedFallbackCanBeConsumedOnlyOnce() {
        let url = URL(fileURLWithPath: "/tmp/problem.mp3")
        var fallback = MPVFailureFallback()
        fallback.arm(for: url)

        XCTAssertEqual(fallback.takeURL(), url)
        XCTAssertNil(fallback.takeURL())
    }

    func testArmingNewTrackReplacesOldFallback() {
        let firstURL = URL(fileURLWithPath: "/tmp/first.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/second.mp3")
        var fallback = MPVFailureFallback()
        fallback.arm(for: firstURL)
        fallback.arm(for: secondURL)

        XCTAssertEqual(fallback.takeURL(), secondURL)
    }

    func testClearingFallbackPreventsRetry() {
        var fallback = MPVFailureFallback()
        fallback.arm(for: URL(fileURLWithPath: "/tmp/problem.mp3"))
        fallback.clear()

        XCTAssertNil(fallback.takeURL())
    }
}
