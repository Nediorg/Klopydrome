import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class AutomixPreloaderLifecycleTests: XCTestCase {

    private func mockSong(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    func testPreloadedMPVEngineIsLazyAndCleanedUpOnReset() {
        let player = Player()
        XCTAssertNil(player.automix.preloadedMPVEngine)

        let engine = player.preparePreloadedMPVEngine()
        XCTAssertNotNil(player.automix.preloadedMPVEngine)
        XCTAssertTrue(player.automix.preloadedMPVEngine === engine)

        player.resetPreloadedNext()
        XCTAssertNil(player.automix.preloadedMPVEngine)
    }

    func testPromotingPreloadedTrackReleasesPreloadedEngine() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song = mockSong("next")
        player.queue = [song]
        player.automix.preloadedNextSong = song
        player.automix.preloadedNextSongID = song.id
        let engine = player.preparePreloadedMPVEngine()
        engine.setIsLoadedForTesting(true)

        let promoted = player.promotePreloadedMPVTrack(for: song, autoPlay: false)
        XCTAssertTrue(promoted)
        XCTAssertTrue(player.mpvEngine === engine)
        XCTAssertNil(player.automix.preloadedMPVEngine)
    }

    func testDisablingNextTrackPreloadReleasesPreloadedEngineImmediately() {
        let player = Player()
        _ = player.preparePreloadedMPVEngine()
        XCTAssertNotNil(player.automix.preloadedMPVEngine)

        player.configureNextTrackPreloading(enabled: false)
        XCTAssertNil(player.automix.preloadedMPVEngine)
    }
}
