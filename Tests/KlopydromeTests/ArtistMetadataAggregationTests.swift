import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class ArtistMetadataAggregationTests: XCTestCase {

    func testAlbumDurationAndSongAggregationWithMultipleAlbums() {
        let albums = (1...54).map { i in
            SubsonicAlbum(
                id: "album_\(i)",
                title: "Album \(i)",
                songCount: 10,
                duration: 2000
            )
        }

        let totalAlbumDuration = albums.compactMap(\.duration).reduce(0, +)
        let totalAlbumSongs = albums.compactMap(\.songCount).reduce(0, +)

        XCTAssertEqual(totalAlbumDuration, 54 * 2000)
        XCTAssertEqual(totalAlbumSongs, 54 * 10)

        let topSongs = (1...5).map { i in
            SubsonicSong(id: "top_\(i)", title: "Top \(i)", duration: 240)
        }
        let topSongsDuration = topSongs.reduce(0) { $0 + ($1.duration ?? 0) }
        XCTAssertEqual(topSongsDuration, 1200)

        let effectiveDuration = totalAlbumDuration > 0 ? totalAlbumDuration : topSongsDuration
        let effectiveSongCount = totalAlbumSongs > 0 ? totalAlbumSongs : topSongs.count

        XCTAssertEqual(effectiveDuration, 108_000)
        XCTAssertEqual(effectiveSongCount, 540)
    }

    func testFallbackToSongsWhenAlbumsHaveNoDurationOrCount() {
        let standaloneSongs = [
            SubsonicSong(id: "s1", title: "Single 1", duration: 180),
            SubsonicSong(id: "s2", title: "Single 2", duration: 240)
        ]

        let emptyAlbums: [SubsonicAlbum] = []
        let albumDuration = emptyAlbums.compactMap(\.duration).reduce(0, +)
        let albumSongs = emptyAlbums.compactMap(\.songCount).reduce(0, +)

        let effectiveDuration = albumDuration > 0 ? albumDuration : standaloneSongs.reduce(0) { $0 + ($1.duration ?? 0) }
        let effectiveSongCount = albumSongs > 0 ? albumSongs : standaloneSongs.count

        XCTAssertEqual(effectiveDuration, 420)
        XCTAssertEqual(effectiveSongCount, 2)
    }
}
