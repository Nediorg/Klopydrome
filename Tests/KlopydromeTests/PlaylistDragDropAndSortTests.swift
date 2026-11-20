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

    func testPlaylistTrackSortingPreservesOriginalPlaylistIndex() {
        let songA = SubsonicSong(id: "1", title: "Zebra", artist: "B Artist", duration: 100)
        let songB = SubsonicSong(id: "2", title: "Apple", artist: "A Artist", duration: 200)
        let songC = SubsonicSong(id: "3", title: "Mango", artist: "C Artist", duration: 150)

        let base: [(playlistIndex: Int, song: SubsonicSong)] = [
            (0, songA),
            (1, songB),
            (2, songC)
        ]

        // Sort by title ascending
        let sortedByTitle = base.sorted {
            $0.song.displayTitle.localizedCaseInsensitiveCompare($1.song.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sortedByTitle.map(\.song.title), ["Apple", "Mango", "Zebra"])
        // Verify playlistIndex remains tied to original position
        XCTAssertEqual(sortedByTitle[0].playlistIndex, 1) // Apple was index 1
        XCTAssertEqual(sortedByTitle[1].playlistIndex, 2) // Mango was index 2
        XCTAssertEqual(sortedByTitle[2].playlistIndex, 0) // Zebra was index 0
    }

    func testFeaturedArtistsAggregation() {
        let s1 = SubsonicSong(id: "1", title: "Track 1", artist: "Artist Alpha", coverArt: "cov-1")
        let s2 = SubsonicSong(id: "2", title: "Track 2", artist: "Artist Beta", coverArt: "cov-2")
        let s3 = SubsonicSong(id: "3", title: "Track 3", artist: "Artist Alpha", coverArt: "cov-1")
        let s4 = SubsonicSong(id: "4", title: "Track 4", artist: "Artist Gamma", coverArt: "cov-3")
        let s5 = SubsonicSong(id: "5", title: "Track 5", artist: "Artist Alpha", coverArt: "cov-1")

        let songs = [s1, s2, s3, s4, s5]
        var counts: [String: (id: String, name: String, coverArt: String?, count: Int)] = [:]
        for song in songs {
            guard let rawName = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else { continue }
            let key = rawName.lowercased()
            let artistID = song.artistId ?? key
            if let existing = counts[key] {
                counts[key] = (existing.id, existing.name, existing.coverArt ?? song.coverArt, existing.count + 1)
            } else {
                counts[key] = (artistID, rawName, song.coverArt, 1)
            }
        }

        let featured = counts.values.map {
            PlaylistFeaturedArtist(id: $0.id, name: $0.name, coverArt: $0.coverArt, trackCount: $0.count)
        }.sorted { $0.trackCount > $1.trackCount }

        XCTAssertEqual(featured.count, 3)
        XCTAssertEqual(featured[0].name, "Artist Alpha")
        XCTAssertEqual(featured[0].trackCount, 3)
        XCTAssertEqual(featured[1].trackCount, 1)
        XCTAssertEqual(featured[2].trackCount, 1)
    }
}
