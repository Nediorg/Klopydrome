import XCTest
@testable import Klopydrome

@MainActor
final class MPVPlaybackEngineFailureTests: XCTestCase {
    func testRuntimeFailureNotifiesOnce() {
        let engine = MPVPlaybackEngine()
        var messages: [String] = []
        engine.onFailure = { messages.append($0) }

        engine.handleTrackFailure(errorCode: -12)
        engine.handleTrackFailure(errorCode: -12)

        XCTAssertEqual(messages, ["MPV could not open the audio stream (code -12)."])
    }
}
