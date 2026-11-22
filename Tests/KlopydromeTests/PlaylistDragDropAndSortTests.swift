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
}
