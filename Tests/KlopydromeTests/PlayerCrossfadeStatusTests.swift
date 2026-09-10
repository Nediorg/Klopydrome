import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class PlayerCrossfadeStatusTests: XCTestCase {
    private func song(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id)
    }

    func testDisplaySongSwitchesToIncomingTrackWhenCrossfadeStarts() {
        let player = Player()
        player.queue = [song("outgoing"), song("incoming")]
        player.currentIndex = 0
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "incoming",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(player.currentSong?.id, "outgoing")
        XCTAssertEqual(player.displaySong?.id, "incoming")

        player.isCrossfading = false
        XCTAssertEqual(player.displaySong?.id, "outgoing")
    }

    func testStatusIsAbsentWithoutActiveCrossfade() {
        let player = Player()

        XCTAssertNil(player.crossfadeRemainingTime)
        XCTAssertNil(player.crossfadeStatusText)
    }

    func testPreparedTransitionDoesNotShowStatusBeforeOverlapStarts() {
        let player = Player()
        player.currentTime = 12
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.crossfadeStatusText)
    }

    func testStatusShowsRemainingOverlapTime() {
        let player = Player()
        player.currentTime = 12
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(try XCTUnwrap(player.crossfadeRemainingTime), 3, accuracy: 0.001)
        XCTAssertEqual(player.crossfadeStatusText, "Crossfade · 3 s")
    }

    func testStatusRoundsPartialSecondUpForTheListener() {
        let player = Player()
        player.currentTime = 12.2
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(player.crossfadeStatusText, "Crossfade · 3 s")
    }
}
