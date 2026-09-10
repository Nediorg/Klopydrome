import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlayerPreloadTests: XCTestCase {
    private func song(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    private func player(
        currentIndex: Int = 0,
        repeatMode: Player.RepeatMode = .off
    ) -> Player {
        let player = Player()
        player.queue = [song("one"), song("two"), song("three")]
        player.currentIndex = currentIndex
        player.repeatMode = repeatMode
        return player
    }

    func testPreloadSelectsImmediateQueueSuccessor() {
        XCTAssertEqual(player().nextSongForPreloading?.id, "two")
    }

    func testPreloadWrapsAtQueueEndOnlyWhenRepeatAll() {
        XCTAssertNil(player(currentIndex: 2).nextSongForPreloading)
        XCTAssertEqual(
            player(currentIndex: 2, repeatMode: .all).nextSongForPreloading?.id,
            "one"
        )
    }

    func testPreloadSkipsRepeatOneAndInvalidQueuePositions() {
        XCTAssertNil(player(repeatMode: .one).nextSongForPreloading)
        let invalid = player(currentIndex: 3)
        XCTAssertNil(invalid.nextSongForPreloading)
    }
}
