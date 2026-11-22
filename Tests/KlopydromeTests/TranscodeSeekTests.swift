import XCTest
import Foundation
import NavidromeClient
@testable import Klopydrome

final class TranscodeSeekTests: XCTestCase {
    private func params(of url: URL) -> [String: String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value ?? ""
            } ?? [:]
    }

    func testTranscodeURLGetsTimeOffsetPreservingOtherParams() throws {
        let base = try XCTUnwrap(URL(
            string: "http://host/rest/stream?id=abc&maxBitRate=128&format=opus"
        ))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: 123.4))
        let params = params(of: url)
        XCTAssertEqual(params["format"], "opus")
        XCTAssertEqual(params["maxBitRate"], "128")
        XCTAssertEqual(params["id"], "abc")
        XCTAssertEqual(params["timeOffset"], "123")
    }

    func testTranscodeURLReplacesExistingTimeOffset() throws {
        let base = try XCTUnwrap(URL(string: "http://host/rest/stream?id=abc&format=opus&timeOffset=5"))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: 30))
        let params = params(of: url)
        XCTAssertEqual(params["timeOffset"], "30")
    }

    func testTranscodeURLClampsNegativeTargetToZero() throws {
        let base = try XCTUnwrap(URL(string: "http://host/rest/stream?id=abc&format=opus"))
        let url = try XCTUnwrap(Player.transcodedSeekURL(from: base, at: -5))
        XCTAssertEqual(params(of: url)["timeOffset"], "0")
    }

    func testDetectsRemoteTranscodeStream() throws {
        XCTAssertTrue(Player.isRemoteTranscodeStreamURL(URL(
            string: "http://host/rest/stream?id=abc&format=opus"
        )))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(URL(string: "http://host/rest/stream?id=abc")))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(nil))
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(URL(fileURLWithPath: "/tmp/song.opus")))
    }

    @MainActor
    func testSeekNeedsTranscodeRestartBehavior() throws {
        let player = Player()
        XCTAssertFalse(player.seekNeedsTranscodeRestart(to: 30))

        // Direct stream (no format param)
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc")
        XCTAssertFalse(player.seekNeedsTranscodeRestart(to: 30))

        // Remote transcode stream (format=opus)
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvStreamOffset = 10
        // Real position = 10 + 0 = 10
        // Target 15 -> distance 5 >= 1.0 -> needs restart
        XCTAssertTrue(player.seekNeedsTranscodeRestart(to: 15))
        // Target 10.4 -> distance 0.4 < 1.0 -> no restart
        XCTAssertFalse(player.seekNeedsTranscodeRestart(to: 10.4))
        // Target 0 -> distance 10 >= 1.0 -> needs restart
        XCTAssertTrue(player.seekNeedsTranscodeRestart(to: 0))
    }

    @MainActor
    func testHandleMPVTimeUpdateBeforeRestartSteppedPreservesSeekRestartActive() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 180)]
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvEngine.setIsLoadedForTesting(true)

        player.performTranscodeRestart(at: 60.0)
        player.mpvEngine.onTimeUpdate?(12.0)

        XCTAssertTrue(player.mpvSeekRestartActive)
        XCTAssertEqual(player.currentTime, 60.0, accuracy: 0.001)
    }

    @MainActor
    func testSetTranscodeSeekWhileBufferingDoesNotStickSeekInFlight() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 180)]
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvEngine.setIsLoadedForTesting(true)
        player.mpvEngine.updateBuffering(true)

        player.seek(to: 50.0)

        XCTAssertEqual(player.pendingSeekTime, 50.0)
        XCTAssertFalse(player.isSeekInFlight)
        XCTAssertNil(player.heldSeekTarget)
    }

    @MainActor
    func testSetTranscodeSeekNearEndClampsRestartOffsetAwayFromEOF() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 200)]
        player.duration = 200
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvEngine.setIsLoadedForTesting(true)

        player.seek(to: 199.5)

        XCTAssertLessThanOrEqual(player.mpvStreamOffset, 198.0)
    }

    @MainActor
    func testTranscodeSeekNothingToPlayEndsTrackInsteadOfFailing() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 200)]
        player.duration = 200
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvSeekRestartActive = true
        player.mpvStreamOffset = 196
        player.mpvFallbackError = "nothing_to_play"
        var ended = false
        player.onTrackEnded = { ended = true }

        player.handleEngineFailure("MPV error -16")

        XCTAssertTrue(ended)
        XCTAssertFalse(player.hasReportedFailure)
        XCTAssertNil(player.lastError)
        XCTAssertFalse(player.mpvSeekRestartActive)
    }

    @MainActor
    func testInitialLoadNothingToPlayStillReportsFailure() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 200)]
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvSeekRestartActive = false
        player.mpvFallbackError = "nothing_to_play"
        var ended = false
        player.onTrackEnded = { ended = true }

        player.handleEngineFailure("MPV error -16")

        XCTAssertFalse(ended)
        XCTAssertTrue(player.hasReportedFailure)
        XCTAssertEqual(player.lastError, "MPV error -16")
    }

    func testIsRemoteTranscodeStreamURLHonorsRawAndMaxBitRate() {
        XCTAssertFalse(Player.isRemoteTranscodeStreamURL(URL(string: "http://host/rest/stream?id=abc&format=raw")))
        XCTAssertTrue(Player.isRemoteTranscodeStreamURL(URL(string: "http://host/rest/stream?id=abc&maxBitRate=192")))
        XCTAssertTrue(Player.isRemoteTranscodeStreamURL(URL(string: "http://host/rest/stream?id=abc&format=opus")))
    }

    @MainActor
    func testSeekDoesNotRestartTranscodeWhenMPVEngineIsSeekableAtZeroOffset() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = [SubsonicSong(id: "s1", title: "S1", duration: 200)]
        player.duration = 200
        player.currentSourceURL = URL(string: "http://host/rest/stream?id=abc&format=opus")
        player.mpvEngine.setIsLoadedForTesting(true)
        player.mpvEngine.setSeekable(true)
        player.mpvStreamOffset = 0

        player.seek(to: 80.0)

        XCTAssertFalse(player.mpvSeekRestartActive)
        XCTAssertEqual(player.mpvStreamOffset, 0)
    }
}
