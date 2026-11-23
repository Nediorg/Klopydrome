import XCTest
@testable import Klopydrome
import NavidromeClient

final class PlaylistDragDropAndSortTests: XCTestCase {
    func testTrackDragPayloadCodableRoundTrip() throws {
        let payload1 = TrackDragPayload.song("s-1")
        let data1 = try JSONEncoder().encode(payload1)
        let decoded1 = try JSONDecoder().decode(TrackDragPayload.self, from: data1)
        XCTAssertEqual(payload1, decoded1)

        let payload2 = TrackDragPayload.songs(["s-1", "s-2", "s-3"])
        let data2 = try JSONEncoder().encode(payload2)
        let decoded2 = try JSONDecoder().decode(TrackDragPayload.self, from: data2)
        XCTAssertEqual(payload2, decoded2)

        let payload3 = TrackDragPayload.queueItem(index: 4, songID: "s-4")
        let data3 = try JSONEncoder().encode(payload3)
        let decoded3 = try JSONDecoder().decode(TrackDragPayload.self, from: data3)
        XCTAssertEqual(payload3, decoded3)

        let payload4 = TrackDragPayload.playlistTrack(playlistID: "pl-1", index: 2, songID: "s-2")
        let data4 = try JSONEncoder().encode(payload4)
        let decoded4 = try JSONDecoder().decode(TrackDragPayload.self, from: data4)
        XCTAssertEqual(payload4, decoded4)
    }

    @MainActor
    func testResolveSongsByIDs() {
        let app = AppState()
        let song1 = SubsonicSong(id: "s-1", title: "Song 1", album: "Album 1", artist: "Artist A")
        let song2 = SubsonicSong(id: "s-2", title: "Song 2", album: "Album 2", artist: "Artist B")
        let song3 = SubsonicSong(id: "s-3", title: "Song 3", album: "Album 1", artist: "Artist A")

        app.player.setQueue([song1, song2])
        app.downloadedSongs = [song3]

        let resolved = app.resolveSongs(byIDs: ["s-3", "s-1", "non-existent"])
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].id, "s-3")
        XCTAssertEqual(resolved[1].id, "s-1")
    }

    @MainActor
    func testResolveSongsIncludesFavoritesAndHistory() {
        let app = AppState()
        let favSong = SubsonicSong(id: "fav-1", title: "Track Fav", artist: "Artist A")
        let histSong = SubsonicSong(id: "hist-1", title: "Track Hist", artist: "Artist B")

        app.library.favoritesSongs = [favSong]
        app.player.history = [histSong]

        let resolved = app.resolveSongs(byIDs: ["hist-1", "fav-1"])
        XCTAssertEqual(resolved.map(\.id), ["hist-1", "fav-1"])
    }

    @MainActor
    func testPlaylistReorderedDestinationMath() {
        XCTAssertEqual(PlaylistDetailView.reorderedDestination(from: 0, to: 3, count: 4), 2)
        XCTAssertEqual(PlaylistDetailView.reorderedDestination(from: 0, to: 4, count: 4), 3)
        XCTAssertEqual(PlaylistDetailView.reorderedDestination(from: 3, to: 1, count: 4), 1)
        XCTAssertEqual(PlaylistDetailView.reorderedDestination(from: 3, to: 0, count: 4), 0)
        XCTAssertNil(PlaylistDetailView.reorderedDestination(from: 1, to: 1, count: 4))
        XCTAssertNil(PlaylistDetailView.reorderedDestination(from: 1, to: 2, count: 4))
    }

    @MainActor
    func testQueueMoveDestinationSupportsEndOfQueueWithoutOutOfBounds() {
        XCTAssertEqual(QueuePanelView.queueMoveDestination(from: 0, to: 3, count: 3), 3)
        XCTAssertEqual(QueuePanelView.queueMoveDestination(from: 0, to: 2, count: 3), 2)
        XCTAssertEqual(QueuePanelView.queueMoveDestination(from: 2, to: 0, count: 3), 0)
        XCTAssertNil(QueuePanelView.queueMoveDestination(from: 0, to: 0, count: 3))
        XCTAssertNil(QueuePanelView.queueMoveDestination(from: 0, to: 1, count: 3))

        let player = Player()
        let songs = (0..<3).map { SubsonicSong(id: "q-\($0)", title: "Track \($0)", artist: "Artist") }
        player.setQueue(songs, startAt: 0, autoPlay: false, recordHistory: false)

        if let dest = QueuePanelView.queueMoveDestination(from: 0, to: player.queue.count, count: player.queue.count) {
            player.move(fromOffsets: IndexSet(integer: 0), toOffset: dest)
        }
        XCTAssertEqual(player.queue.map(\.id), ["q-1", "q-2", "q-0"])
    }
}
