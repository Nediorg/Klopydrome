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

    func testOpenArtistInLibraryFromPlaylistPreservesSelectedPlaylist() {
        let app = AppState()
        let playlist = PlaylistSummary(id: "pl-1", name: "PL", songCount: 3)
        app.nav.selectedPlaylist = playlist
        let artist = Artist(id: "art-1", name: "Daft Punk")

        app.openArtistInLibrary(artist)

        XCTAssertEqual(app.nav.history.last, .artist(artist))
        XCTAssertEqual(app.nav.selectedPlaylist?.id, "pl-1")

        app.navigateBack()
        XCTAssertTrue(app.nav.history.isEmpty)
        XCTAssertEqual(app.nav.selectedPlaylist?.id, "pl-1")
    }

    func testOpenAlbumInLibraryFromPlaylistPreservesSelectedPlaylist() {
        let app = AppState()
        let playlist = PlaylistSummary(id: "pl-1", name: "PL", songCount: 3)
        app.nav.selectedPlaylist = playlist
        let album = SubsonicAlbum(id: "alb-1", title: "Discovery")

        app.openAlbumInLibrary(album)

        XCTAssertEqual(app.nav.history.last, .album(album))
        XCTAssertEqual(app.nav.selectedPlaylist?.id, "pl-1")

        app.navigateBack()
        XCTAssertTrue(app.nav.history.isEmpty)
        XCTAssertEqual(app.nav.selectedPlaylist?.id, "pl-1")
    }

    // MARK: - Login Overlay Visibility

    func testShouldShowLoginViewGatesTransitions() {
        let app = AppState()
        // Launch gate suppresses login
        XCTAssertTrue(app.isLaunching)
        XCTAssertFalse(app.shouldShowLoginView)

        // Post-launch idle disconnected state shows login
        app.isLaunching = false
        XCTAssertTrue(app.shouldShowLoginView)

        // Preparing offline session suppresses login
        app.isPreparingOfflineSession = true
        XCTAssertFalse(app.shouldShowLoginView)
        app.isPreparingOfflineSession = false
        XCTAssertTrue(app.shouldShowLoginView)

        // Active offline session suppresses login
        app.isOfflineSession = true
        XCTAssertFalse(app.shouldShowLoginView)
        app.isOfflineSession = false
        XCTAssertTrue(app.shouldShowLoginView)

        // Foreground reconnect suppresses login
        app.isReconnecting = true
        XCTAssertFalse(app.shouldShowLoginView)
        app.isReconnecting = false
        XCTAssertTrue(app.shouldShowLoginView)

        // Background reconnect suppresses login
        app.isBackgroundReconnecting = true
        XCTAssertFalse(app.shouldShowLoginView)
        app.isBackgroundReconnecting = false
        XCTAssertTrue(app.shouldShowLoginView)
    }
}
