import Foundation
import XCTest
@testable import Klopydrome

@MainActor
final class MPVEngineTests: XCTestCase {

    // MARK: - Failure Fallback

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

    // MARK: - Engine Runtime Failures

    func testRuntimeFailureNotifiesOnce() {
        let engine = MPVPlaybackEngine()
        var messages: [String] = []
        engine.onFailure = { messages.append($0) }

        engine.handleTrackFailure(errorCode: -12)
        engine.handleTrackFailure(errorCode: -12)

        XCTAssertEqual(messages, ["MPV could not open the audio stream (code -12)."])
    }

    func testBufferingNotificationWhenPausedForCache() {
        let engine = MPVPlaybackEngine()
        var bufferingStates: [Bool] = []
        engine.onBufferingUpdate = { bufferingStates.append($0) }

        engine.setPausedForCache(true)
        XCTAssertTrue(engine.isBuffering)
        XCTAssertEqual(bufferingStates, [true])

        engine.setPausedForCache(false)
        XCTAssertFalse(engine.isBuffering)
        XCTAssertEqual(bufferingStates, [true, false])
    }

    func testFileLoadedNotification() {
        let engine = MPVPlaybackEngine()
        var fileLoaded = false
        engine.onFileLoaded = { fileLoaded = true }

        XCTAssertFalse(engine.isLoaded)
        engine.handleFileLoaded()
        XCTAssertTrue(engine.isLoaded)
        XCTAssertTrue(fileLoaded)
    }

    func testSeekFailsWhenNotLoaded() {
        let engine = MPVPlaybackEngine()
        XCTAssertFalse(engine.isLoaded)
        let accepted = engine.seek(to: 45.0)
        XCTAssertFalse(accepted, "Seek must not succeed before file is loaded")
    }

    func testSeekableNotification() {
        let engine = MPVPlaybackEngine()
        var seekableStates: [Bool] = []
        engine.onSeekableUpdate = { seekableStates.append($0) }

        engine.setSeekable(true)
        XCTAssertTrue(engine.isSeekable)
        XCTAssertEqual(seekableStates, [true])
    }
}
