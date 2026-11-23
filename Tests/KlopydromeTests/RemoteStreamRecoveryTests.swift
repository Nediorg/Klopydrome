import Foundation
import NavidromeClient
import XCTest
@testable import Klopydrome

@MainActor
final class RemoteStreamRecoveryTests: XCTestCase {
    private func makeRemotePlayer(urlString: String = "https://example.com/rest/stream?id=track1") -> Player {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "track1", title: "Sample Track", duration: 240)]
        player.currentIndex = 0
        player.currentSourceURL = URL(string: urlString)
        player.duration = 240
        player.currentTime = 45
        player.isPlaying = true
        return player
    }

    func testHandleEngineFailureRetriesRemoteStreamUpToLimitThenStops() {
        let player = makeRemotePlayer()

        player.handleEngineFailure("Network error")
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.isBuffering)
        XCTAssertFalse(player.hasReportedFailure)
        XCTAssertNil(player.lastError)
        XCTAssertEqual(player.remoteStreamRetryCount, 1)

        player.handleEngineFailure("Network error")
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(player.isBuffering)
        XCTAssertFalse(player.hasReportedFailure)
        XCTAssertEqual(player.remoteStreamRetryCount, 2)

        player.handleEngineFailure("Network error")
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isBuffering)
        XCTAssertFalse(player.isLoading)
        XCTAssertTrue(player.hasReportedFailure)
        XCTAssertEqual(player.lastError, "Network error")
        XCTAssertEqual(player.remoteStreamRetryCount, 0)

        player.stop()
    }

    func testPrematureRemoteEOFRecoversMidTrackOnly() {
        let player = makeRemotePlayer()

        player.currentTime = 90
        XCTAssertTrue(player.recoverFromPrematureRemoteEOFIfNeeded())
        XCTAssertEqual(player.remoteStreamRetryCount, 1)
        XCTAssertTrue(player.isBuffering)

        player.resetRemoteStreamRecovery()
        player.currentTime = 235
        XCTAssertFalse(player.recoverFromPrematureRemoteEOFIfNeeded())
        XCTAssertEqual(player.remoteStreamRetryCount, 0)

        player.currentTime = 90
        player.currentSourceURL = URL(fileURLWithPath: "/tmp/sample.opus")
        XCTAssertFalse(player.recoverFromPrematureRemoteEOFIfNeeded())

        player.stop()
    }

    func testRemotePlaybackProgressResetsRetryBudget() {
        let player = makeRemotePlayer()
        player.currentTime = 60

        XCTAssertTrue(player.recoverRemoteStreamIfPossible(at: 60))
        XCTAssertEqual(player.remoteStreamRetryCount, 1)

        player.noteRemotePlaybackProgress(at: 61.5)
        XCTAssertEqual(player.remoteStreamRetryCount, 1)

        player.noteRemotePlaybackProgress(at: 63.5)
        XCTAssertEqual(player.remoteStreamRetryCount, 0)

        player.stop()
    }

    func testPauseCancelsPendingRemoteRecoveryTask() {
        let player = makeRemotePlayer()

        XCTAssertTrue(player.recoverRemoteStreamIfPossible(at: 45))
        XCTAssertNotNil(player.remoteStreamRecoveryTask)

        player.pause()
        XCTAssertNil(player.remoteStreamRecoveryTask)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isBuffering)

        player.stop()
    }

    func testMPVNetworkReconnectOptionsInitializeCleanly() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil)
        let engine = MPVPlaybackEngine()
        var failureMessage: String?
        engine.onFailure = { failureMessage = $0 }

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NavidromeClientTests/Fixtures/sine300.opus")

        try await engine.load(url: fixtureURL)
        engine.play()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(failureMessage)
        engine.stop()
    }
}
