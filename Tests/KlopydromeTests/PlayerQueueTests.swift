import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlayerQueueTests: XCTestCase {

    // MARK: - Successor Preloading

    private func makeSong(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    private func makePreloadPlayer(
        currentIndex: Int = 0,
        repeatMode: Player.RepeatMode = .off
    ) -> Player {
        let player = Player()
        player.queue = [makeSong("one"), makeSong("two"), makeSong("three")]
        player.currentIndex = currentIndex
        player.repeatMode = repeatMode
        return player
    }

    func testPreloadSelectsImmediateQueueSuccessor() {
        XCTAssertEqual(makePreloadPlayer().nextSongForPreloading?.id, "two")
    }

    func testPreloadWrapsAtQueueEndOnlyWhenRepeatAll() {
        XCTAssertNil(makePreloadPlayer(currentIndex: 2).nextSongForPreloading)
        XCTAssertEqual(
            makePreloadPlayer(currentIndex: 2, repeatMode: .all).nextSongForPreloading?.id,
            "one"
        )
    }

    func testPreloadSkipsRepeatOneAndInvalidQueuePositions() {
        XCTAssertNil(makePreloadPlayer(repeatMode: .one).nextSongForPreloading)
        let invalid = makePreloadPlayer(currentIndex: 3)
        XCTAssertNil(invalid.nextSongForPreloading)
    }

    // MARK: - Queue Shuffling

    private func makeShuffleSong(
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

    private func makeShufflePlayer() -> Player {
        let player = Player()
        player.queue = [
            makeShuffleSong("a1", album: "A", artist: "Artist A"),
            makeShuffleSong("a2", album: "A", artist: "Artist A"),
            makeShuffleSong("b1", album: "B", artist: "Artist B"),
            makeShuffleSong("b2", album: "B", artist: "Artist B"),
            makeShuffleSong("c1", album: "C", artist: "Artist C"),
            makeShuffleSong("c2", album: "C", artist: "Artist C")
        ]
        player.currentIndex = 0
        return player
    }

    func testModeCanBeSelectedBeforeShuffleIsEnabled() {
        let player = makeShufflePlayer()
        player.setShuffleMode(.albums)

        XCTAssertFalse(player.shuffle)
        XCTAssertEqual(player.shuffleMode, .albums)
    }

    func testAlbumShuffleKeepsAlbumTracksContiguousAndRestoresQueue() {
        let player = makeShufflePlayer()
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
        let player = makeShufflePlayer()
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
            makeShuffleSong("a1", album: "A", artist: "Artist A"),
            makeShuffleSong("b1", album: "B", artist: "Artist B"),
            makeShuffleSong("c1", album: "C", artist: "Artist C")
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
