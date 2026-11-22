import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class AutomixPreloaderLifecycleTests: XCTestCase {

    private func mockSong(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    func testTrackDidFinishSeamlesslyPromotesPreloadedTrackWithoutStoppingEngine() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("song1")
        let song2 = mockSong("song2")
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.isPlaying = true

        player.preloadedNextSong = song2
        player.preloadedNextSongID = song2.id
        player.mpvEngine.setHasAppendedTrackForTesting(true, url: URL(string: "https://navidrome.example.com/2")!)

        var promotedSongID: String?
        player.onTrackPromoted = { song in
            promotedSongID = song.id
        }

        XCTAssertTrue(player.hasLoadedPreloadForNextTrack)
        player.trackDidFinish()

        XCTAssertEqual(player.currentIndex, 1)
        XCTAssertEqual(promotedSongID, "song2")
        XCTAssertTrue(player.isPlaying)
    }

    func testEagerPreloadGateTriggersEarlyInTrack() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("song1")
        let song2 = mockSong("song2")
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.isPlaying = true

        var requestedID: String?
        let testURL = URL(string: "https://navidrome.example.com/rest/stream?id=song2")!
        player.onNextTrackPreloadRequest = { song in
            requestedID = song.id
            return testURL
        }

        player.evaluateNextTrackPreload(at: 10.0)
        XCTAssertEqual(requestedID, "song2")
        XCTAssertEqual(player.preloadedNextSongID, "song2")
        XCTAssertTrue(player.mpvEngine.hasAppendedTrack)
        XCTAssertEqual(player.mpvEngine.appendedURL, testURL)
        XCTAssertTrue(player.hasLoadedPreloadForNextTrack)
    }

    func testResetPreloadedNextClearsAppendedTrackFromMPV() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("song1")
        let song2 = mockSong("song2")
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.isPlaying = true

        player.preloadedNextSongID = song2.id
        player.mpvEngine.setHasAppendedTrackForTesting(true, url: URL(string: "https://example.com/2")!)

        XCTAssertTrue(player.hasLoadedPreloadForNextTrack)
        player.resetPreloadedNext()

        XCTAssertFalse(player.hasLoadedPreloadForNextTrack)
        XCTAssertFalse(player.mpvEngine.hasAppendedTrack)
        XCTAssertNil(player.preloadedNextSongID)
    }
}
