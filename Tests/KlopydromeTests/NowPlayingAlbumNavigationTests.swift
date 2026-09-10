import XCTest
@testable import Klopydrome
import NavidromeClient

final class NowPlayingAlbumNavigationTests: XCTestCase {
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

    @MainActor
    func testOpenAlbumInLibraryPublishesMainNavigationIntent() {
        let app = AppState()
        let album = SubsonicAlbum(id: "album-1", title: "Album")

        app.openAlbumInLibrary(album)

        XCTAssertEqual(app.nav.selected, .albums)
        XCTAssertNil(app.nav.selectedPlaylist)
        XCTAssertEqual(app.nav.pendingAlbum, album)
    }

    @MainActor
    func testOpenSongDetailsPublishesPendingSongWithoutTouchingSidebarSelection() {
        let app = AppState()
        app.nav.selectedPlaylist = PlaylistSummary(id: "pl-1", name: "PL", songCount: 3)
        let song = SubsonicSong(id: "song-1", title: "Track")

        app.openSongDetails(song)

        XCTAssertEqual(app.nav.pendingSong, song)
        XCTAssertNotNil(app.nav.selectedPlaylist)
    }
}
