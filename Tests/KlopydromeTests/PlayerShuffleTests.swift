import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlayerShuffleTests: XCTestCase {
    private func song(
        _ id: String,
        album: String,
        artist: String
    ) -> SubsonicSong {
        SubsonicSong(
            id: id,
            title: id,
            album: album,
            artist: artist,
            duration: 180,
            albumArtist: artist
        )
    }

    private func makePlayer() -> Player {
        let player = Player()
        player.queue = [
            song("a1", album: "A", artist: "Artist A"),
            song("a2", album: "A", artist: "Artist A"),
            song("b1", album: "B", artist: "Artist B"),
            song("b2", album: "B", artist: "Artist B"),
            song("c1", album: "C", artist: "Artist C"),
            song("c2", album: "C", artist: "Artist C")
        ]
        player.currentIndex = 0
        return player
    }

    func testModeCanBeSelectedBeforeShuffleIsEnabled() {
        let player = makePlayer()
        player.setShuffleMode(.albums)

        XCTAssertFalse(player.shuffle)
        XCTAssertEqual(player.shuffleMode, .albums)
    }

    func testAlbumShuffleKeepsAlbumTracksContiguousAndRestoresQueue() {
        let player = makePlayer()
        let original = player.queue.map(\.id)
        player.setShuffleMode(.albums)
        player.setShuffleEnabled(true)

        XCTAssertTrue(player.shuffle)
        XCTAssertEqual(player.currentSong?.id, "a1")
        assertContiguous(player.queue, where: { $0.album == "B" })
        assertContiguous(player.queue, where: { $0.album == "C" })

        player.setShuffleEnabled(false)
        XCTAssertFalse(player.shuffle)
        XCTAssertEqual(player.queue.map(\.id), original)
    }

    func testGroupShuffleKeepsArtistTracksContiguous() {
        let player = makePlayer()
        player.setShuffleMode(.groups)
        player.setShuffleEnabled(true)

        assertContiguous(player.queue, where: { $0.artist == "Artist B" })
        assertContiguous(player.queue, where: { $0.artist == "Artist C" })
    }

    func testRestoredShufflePreferenceAppliesWhenQueueLoads() {
        let player = Player()
        player.setShuffleEnabled(true)

        XCTAssertTrue(player.shufflePreferenceEnabled)
        XCTAssertFalse(player.shuffle)

        let songs = [
            song("a1", album: "A", artist: "Artist A"),
            song("b1", album: "B", artist: "Artist B"),
            song("c1", album: "C", artist: "Artist C")
        ]
        player.setQueue(songs, autoPlay: false)

        XCTAssertTrue(player.shufflePreferenceEnabled)
        XCTAssertTrue(player.shuffle)
        XCTAssertEqual(player.queue.count, songs.count)
    }

    private func assertContiguous(
        _ songs: [SubsonicSong],
        where predicate: (SubsonicSong) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let indices = songs.indices.filter { predicate(songs[$0]) }
        XCTAssertGreaterThan(indices.count, 1, file: file, line: line)
        XCTAssertEqual(indices, Array(indices.first!...indices.last!), file: file, line: line)
    }
}
