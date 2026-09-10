import XCTest
@testable import Klopydrome

/// Guards the transient-vs-terminal boundary in `CoverArtStore`: only
/// genuinely dead artwork may latch into `failedKeys`. Everything transient
/// (offline, timeout, cancellation) must retry on the next lookup, or every
/// background nap becomes minutes of dead tiles.
final class CoverArtFailureClassificationTests: XCTestCase {
    private func isTransient(_ error: Error) -> Bool {
        if case .transient = CoverArtStore.classifyFetchError(error) { return true }
        return false
    }

    private func isDead(_ error: Error) -> Bool {
        if case .dead = CoverArtStore.classifyFetchError(error) { return true }
        return false
    }

    func testCancellationIsTransient() {
        XCTAssertTrue(isTransient(CancellationError()))
        XCTAssertTrue(isTransient(URLError(.cancelled)))
    }

    func testConnectivityLossIsTransient() {
        XCTAssertTrue(isTransient(URLError(.timedOut)))
        XCTAssertTrue(isTransient(URLError(.networkConnectionLost)))
        XCTAssertTrue(isTransient(URLError(.notConnectedToInternet)))
    }

    func testUnknownErrorsStayDead() {
        XCTAssertTrue(isDead(URLError(.cannotFindHost)))
        XCTAssertTrue(isDead(URLError(.badServerResponse)))
        XCTAssertTrue(isDead(NSError(domain: "test", code: 1)))
    }

    func testInvalidateClearsWithoutCrashing() {
        // No throw, no precondition: safe to call with an empty registry.
        CoverArtStore.shared.invalidateFailedKeys()
    }
}
