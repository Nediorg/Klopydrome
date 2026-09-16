import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class AppStateNavigationTests: XCTestCase {

    // MARK: - Album Sorting

    private func album(
        _ id: String,
        title: String,
        year: Int? = nil,
        playCount: Int? = nil,
        created: String? = nil
    ) -> SubsonicAlbum {
        SubsonicAlbum(id: id, title: title, playCount: playCount, created: created, year: year)
    }

    func testMissingYearsUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .release, descending: false).map(\.id), ["a", "z"])
    }

    func testMissingPlayCountsUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .playCount, descending: true).map(\.id), ["a", "z"])
    }

    func testMissingCreatedDatesUseNameAsStableTieBreaker() {
        let albums = [album("z", title: "Zulu"), album("a", title: "Alpha")]

        XCTAssertEqual(sortedAlbums(albums, by: .recentlyAdded, descending: false).map(\.id), ["a", "z"])
    }

    // MARK: - Ratings & Star Overrides

    func testToggleStarWithoutClientKeepsOverride() {
        let app = AppState()
        let song = SubsonicSong(id: "s1")
        app.toggleStar(song)
        XCTAssertTrue(app.isStarred(song))
        app.toggleStar(song)
        XCTAssertFalse(app.isStarred(song))
    }

    func testSetRatingWithoutClientKeepsOverride() {
        let app = AppState()
        let song = SubsonicSong(id: "s1", userRating: 2)
        app.setRating(5, for: song)
        XCTAssertEqual(app.effectiveRating(for: song), 5)
    }

    // MARK: - Now Playing & Library Navigation

    func testNowPlayingSummaryPreservesAlbumHeaderMetadata() {
        let song = SubsonicSong(
            id: "song-1",
            title: "Track",
            album: "Album",
            artist: "Track Artist",
            year: 2026,
            genre: "Electronic",
            coverArt: "cover-1",
            albumId: "album-1",
            artistId: "artist-1",
            albumArtist: "Album Artist"
        )

        let album = SubsonicAlbum.nowPlayingSummary(from: song, albumID: "album-1")

        XCTAssertEqual(album.id, "album-1")
        XCTAssertEqual(album.title, "Album")
        XCTAssertEqual(album.album, "Album")
        XCTAssertEqual(album.name, "Album")
        XCTAssertEqual(album.artist, "Album Artist")
        XCTAssertEqual(album.artistId, "artist-1")
        XCTAssertEqual(album.coverArt, "cover-1")
        XCTAssertEqual(album.year, 2026)
        XCTAssertEqual(album.genre, "Electronic")
    }

    func testNowPlayingSummaryUsesTrackArtistWhenAlbumArtistIsMissing() {
        let song = SubsonicSong(id: "song-1", album: "Album", artist: "Track Artist")

        let album = SubsonicAlbum.nowPlayingSummary(from: song, albumID: "album-1")

        XCTAssertEqual(album.artist, "Track Artist")
    }

    func testOpenAlbumInLibraryPublishesMainNavigationIntent() {
        let app = AppState()
        let album = SubsonicAlbum(id: "album-1", title: "Album")

        app.openAlbumInLibrary(album)

        XCTAssertEqual(app.nav.history.last, .album(album))
        XCTAssertNil(app.nav.selectedPlaylist)
    }

    func testOpenSongDetailsPublishesPendingSongWithoutTouchingSidebarSelection() {
        let app = AppState()
        app.nav.selectedPlaylist = PlaylistSummary(id: "pl-1", name: "PL", songCount: 3)
        let song = SubsonicSong(id: "song-1", title: "Track")

        app.openSongDetails(song)

        XCTAssertEqual(app.nav.history.last, .song(song))
        XCTAssertNotNil(app.nav.selectedPlaylist)
    }
}
