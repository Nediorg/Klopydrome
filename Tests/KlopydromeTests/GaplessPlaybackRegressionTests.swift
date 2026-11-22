import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class GaplessPlaybackRegressionTests: XCTestCase {

    private func mockSong(_ id: String = "song", duration: Int? = 180) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: duration)
    }

    private func makePlayer(_ songs: [SubsonicSong]? = nil) -> Player {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.queue = songs ?? [mockSong()]
        player.currentIndex = 0
        return player
    }

    func testBeginScrubClearsInFlightSeekSoPromotedTrackAdvancesTimeAndEOF() {
        let song1 = mockSong("s1", duration: 180)
        let song2 = mockSong("s2", duration: 200)
        let song3 = mockSong("s3", duration: 210)
        let player = makePlayer([song1, song2, song3])
        player.mpvEngine.setIsLoadedForTesting(true)

        player.seek(to: 40.0)
        player.beginScrub()

        player.preloadedNextSong = song2
        player.preloadedNextSongID = song2.id
        player.mpvEngine.setHasAppendedTrackForTesting(true, url: URL(fileURLWithPath: "/tmp/s2.opus"))
        XCTAssertTrue(player.promotePreloadedMPVTrack(for: song2, autoPlay: true))

        player.mpvEngine.onTimeUpdate?(15.0)
        XCTAssertEqual(player.currentTime, 15.0, accuracy: 0.001)

        var trackEndedCalled = false
        player.onTrackEnded = { trackEndedCalled = true }
        player.mpvEngine.onTimeUpdate?(199.5)
        player.mpvEngine.onTrackEnded?()
        XCTAssertTrue(trackEndedCalled)
    }

    func testRepeatOneRestartsTrackWhenMPVEngineHasEnded() {
        let player = makePlayer()
        player.repeatMode = .one
        var requestedIDs: [String] = []
        player.onTrackRequest = { requestedIDs.append($0.id) }

        player.mpvEngine.setIsLoadedForTesting(true)
        player.mpvEngine.handleTrackEnded()
        player.trackDidFinish()

        XCTAssertEqual(requestedIDs, ["song"])
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isSeekInFlight)
    }

    func testStopIncrementsMPVLoadGeneration() {
        let player = makePlayer()
        let generationBefore = player.mpvLoadGeneration

        player.stop()

        XCTAssertGreaterThan(player.mpvLoadGeneration, generationBefore)
    }

    func testOnFileLoadedSyncsPlayerDurationWhenMetadataMissing() {
        let player = makePlayer([mockSong("s1", duration: nil)])
        player.mpvEngine.setDuration(215.5)

        player.mpvEngine.handleFileLoaded()

        XCTAssertEqual(player.duration, 215.5, accuracy: 0.001)
        XCTAssertEqual(player.trackDuration, 215.5, accuracy: 0.001)
    }

    func testOnDurationUpdateSyncsPlayerDurationWithoutWaitingForTimePos() {
        let player = makePlayer([mockSong("s1", duration: nil)])

        player.mpvEngine.setDuration(198.4)

        XCTAssertEqual(player.duration, 198.4, accuracy: 0.001)
        XCTAssertEqual(player.trackDuration, 198.4, accuracy: 0.001)
    }

    func testNextAtEndOfQueueDoesNotLeaveSeekInFlightWhenEngineStopped() {
        let player = makePlayer()
        player.repeatMode = .off
        player.mpvEngine.stop()

        player.next()

        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isSeekInFlight)
        XCTAssertNil(player.pendingSeekTime)
    }

    func testHandleMPVTrackEndedDoesNotRestartTranscodeFromZero() {
        let player = makePlayer()
        player.duration = 180.0
        player.currentTime = 0.0
        player.currentSourceURL = URL(string: "http://example.com/rest/stream?id=song&format=opus")
        var ended = false
        player.onTrackEnded = { ended = true }

        player.mpvEngine.onTrackEnded?()

        XCTAssertTrue(ended)
        XCTAssertFalse(player.mpvSeekRestartActive)
    }

    func testApplyRestoredPlayQueueDoesNotInterruptLoadingOrPlayingTrack() {
        let app = AppState()
        let activeSong = mockSong("active", duration: 200)
        let serverSong = mockSong("server", duration: 180)
        app.player.queue = [activeSong]
        app.player.currentIndex = 0
        app.player.isLoading = true
        app.player.isPlaying = true
        var requestedIDs: [String] = []
        app.player.onTrackRequest = { requestedIDs.append($0.id) }

        app.applyRestoredPlayQueue(entries: [serverSong], targetIndex: 0, positionMs: 45_000)

        XCTAssertEqual(app.player.currentSong?.id, "active")
        XCTAssertTrue(app.player.isPlaying)
        XCTAssertTrue(requestedIDs.isEmpty)
    }
}
