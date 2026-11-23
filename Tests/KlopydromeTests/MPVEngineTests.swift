import Foundation
import XCTest
@testable import Klopydrome

@MainActor
final class MPVEngineTests: XCTestCase {

    // MARK: - Engine Runtime Failures

    func testRuntimeFailureNotifiesOnce() {
        let engine = MPVPlaybackEngine()
        var messages: [String] = []
        engine.onFailure = { messages.append($0) }

        engine.handleTrackFailure(errorCode: -12)
        engine.handleTrackFailure(errorCode: -12)

        XCTAssertEqual(messages, [L10n.format("format.mpv.openFailure", -12)])
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

    func testSilenceTrimDoesNotCrashMPV() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let engine = MPVPlaybackEngine()
        engine.silenceTrimMode = .light
        var failureMessage: String?
        engine.onFailure = { msg in
            failureMessage = msg
        }
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NavidromeClientTests/Fixtures/sine300.opus")
        _ = try await engine.load(url: fixtureURL)
        engine.play()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(failureMessage)
    }

    // MARK: - Gapless Playlist Append

    func testAppendedTrackStateAndClear() {
        let engine = MPVPlaybackEngine()
        XCTAssertFalse(engine.hasAppendedTrack)
        XCTAssertNil(engine.appendedURL)

        let nextURL = URL(string: "https://example.com/next.mp3")!
        engine.append(url: nextURL)
        XCTAssertTrue(engine.hasAppendedTrack)
        XCTAssertEqual(engine.appendedURL, nextURL)

        engine.clearAppended()
        XCTAssertFalse(engine.hasAppendedTrack)
        XCTAssertNil(engine.appendedURL)
    }

    func testHandleTrackEndedWithAppendedTrackDoesNotEndPlayback() {
        let engine = MPVPlaybackEngine()
        engine.setIsPlayingForTesting(true)
        let nextURL = URL(string: "https://example.com/next.mp3")!
        engine.setHasAppendedTrackForTesting(true, url: nextURL)

        var trackEndedCalled = false
        engine.onTrackEnded = {
            trackEndedCalled = true
        }

        engine.handleTrackEnded()

        XCTAssertTrue(trackEndedCalled)
        XCTAssertFalse(engine.hasAppendedTrack)
        XCTAssertNil(engine.appendedURL)
        XCTAssertFalse(engine.isEnded)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.duration, 0)
    }

    func testHandleTrackEndedWithoutAppendedTrackMarksNotLoaded() {
        let engine = MPVPlaybackEngine()
        engine.setIsLoadedForTesting(true)
        engine.setIsPlayingForTesting(true)

        engine.handleTrackEnded()

        XCTAssertFalse(engine.isLoaded)
        XCTAssertTrue(engine.isEnded)
        XCTAssertFalse(engine.isPlaying)
    }

    func testStopClearsDurationAndSeekable() {
        let engine = MPVPlaybackEngine()
        engine.setDuration(123.4)
        engine.setSeekable(true)

        engine.stop()

        XCTAssertEqual(engine.duration, 0)
        XCTAssertFalse(engine.isSeekable)
    }

    func testClearAppendedAlwaysResetsDidAdvanceFlag() {
        let engine = MPVPlaybackEngine()
        engine.setDidAdvanceToAppendedTrackForTesting(true)

        engine.clearAppended()

        XCTAssertFalse(engine.didAdvanceToAppendedTrack)
    }

    func testStaleEndFileWithMismatchedEntryIDDoesNotClearDurationOrEndTrack() {
        let engine = MPVPlaybackEngine()
        engine.setEntryIDsForTesting(active: 20, appended: nil)
        engine.setIsLoadedForTesting(true)
        engine.setIsPlayingForTesting(true)
        engine.setDuration(195.0)
        var ended = false
        engine.onTrackEnded = { ended = true }

        engine.handleEndFile(entryID: 10, reason: .eof, errorCode: 0)

        XCTAssertFalse(ended)
        XCTAssertTrue(engine.isLoaded)
        XCTAssertFalse(engine.isEnded)
        XCTAssertEqual(engine.duration, 195.0)
        XCTAssertEqual(engine.activeEntryID, 20)
    }

    func testAppendedEntryErrorDoesNotFailActiveTrack() {
        let engine = MPVPlaybackEngine()
        engine.setEntryIDsForTesting(active: 10, appended: 11)
        engine.setIsLoadedForTesting(true)
        engine.setIsPlayingForTesting(true)
        engine.setHasAppendedTrackForTesting(true, url: URL(string: "https://example.com/broken.opus")!)
        var failed = false
        engine.onFailure = { _ in failed = true }

        engine.handleEndFile(entryID: 11, reason: .error, errorCode: -13)

        XCTAssertFalse(failed)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertFalse(engine.isEnded)
        XCTAssertFalse(engine.hasAppendedTrack)
        XCTAssertNil(engine.appendedEntryID)
        XCTAssertEqual(engine.activeEntryID, 10)
    }

    func testGaplessRealOpusAssignsDistinctEntryIDsAndUpdatesDuration() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let engine = MPVPlaybackEngine()
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NavidromeClientTests/Fixtures/sine300.opus")

        var fileLoadedCount = 0
        engine.onFileLoaded = { fileLoadedCount += 1 }
        _ = try await engine.load(url: fixtureURL)
        let firstEntryID = engine.activeEntryID
        engine.append(url: fixtureURL)
        let secondEntryID = engine.appendedEntryID
        engine.play()

        for _ in 0..<40 where fileLoadedCount < 1 || engine.duration <= 0 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertNotNil(firstEntryID)
        XCTAssertNotNil(secondEntryID)
        XCTAssertNotEqual(firstEntryID, secondEntryID)
        XCTAssertGreaterThan(fileLoadedCount, 0)
        XCTAssertGreaterThan(engine.duration, 0)
        engine.stop()
    }

    func testStalePropertyChangeWithMismatchedEntryIDIsIgnored() {
        let engine = MPVPlaybackEngine()
        engine.setEntryIDsForTesting(active: 20, appended: nil)
        engine.setDuration(180.0)
        var timeUpdates: [Double] = []
        engine.onTimeUpdate = { timeUpdates.append($0) }

        engine.setDuration(10.0, entryID: 10)
        engine.applyTimePos(99.0, entryID: 10)
        engine.setSeekable(true, entryID: 10)

        XCTAssertEqual(engine.duration, 180.0)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertFalse(engine.isSeekable)
        XCTAssertTrue(timeUpdates.isEmpty)
    }

    func testSilenceTrimModeAppliedOnInitialEnsureMpv() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let engine = MPVPlaybackEngine()
        engine.silenceTrimMode = .light
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NavidromeClientTests/Fixtures/sine300.opus")

        try await engine.load(url: fixtureURL)
        XCTAssertEqual(engine.silenceTrimMode, .light)
        engine.stop()
    }

    func testSkipToAppendedTrackRealOpusUpdatesEntryIDAndDuration() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let engine = MPVPlaybackEngine()
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NavidromeClientTests/Fixtures/sine300.opus")

        var fileLoadedCount = 0
        engine.onFileLoaded = { fileLoadedCount += 1 }
        try await engine.load(url: fixtureURL)
        engine.play()

        for _ in 0..<40 where fileLoadedCount < 1 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        engine.append(url: fixtureURL)
        let secondEntryID = try XCTUnwrap(engine.appendedEntryID)

        engine.skipToAppendedTrack(autoPlay: true)
        for _ in 0..<40 where fileLoadedCount < 2 || engine.duration <= 0 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(engine.activeEntryID, secondEntryID)
        XCTAssertFalse(engine.hasAppendedTrack)
        XCTAssertNil(engine.appendedEntryID)
        XCTAssertFalse(engine.isEnded)
        XCTAssertGreaterThan(fileLoadedCount, 1)
        XCTAssertGreaterThan(engine.duration, 0)
        engine.stop()
    }
}
