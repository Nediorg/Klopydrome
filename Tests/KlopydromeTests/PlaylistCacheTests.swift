import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlaylistCacheTests: XCTestCase {
    private func summary(changed: String? = "2026-08-18T12:00:00Z", count: Int? = 2) -> PlaylistSummary {
        PlaylistSummary(
            id: "playlist",
            name: "Playlist",
            songCount: count,
            changed: changed
        )
    }

    private func detail(changed: String? = "2026-08-18T12:00:00Z", count: Int? = 2) -> PlaylistDetail {
        PlaylistDetail(
            id: "playlist",
            name: "Playlist",
            songCount: count,
            changed: changed,
            entry: [
                SubsonicSong(id: "first", title: "First"),
                SubsonicSong(id: "second", title: "Second")
            ]
        )
    }

    // MARK: - Manifest & Timestamp Caching

    func testMatchingManifestReusesCachedPlaylistDetail() {
        let app = AppState()
        let cached = detail()
        app.cachePlaylistDetail(cached)

        let result = app.cachedPlaylistDetail(for: summary())

        XCTAssertEqual(result, cached)
    }

    func testChangedTimestampInvalidatesCachedPlaylistDetail() {
        let app = AppState()
        app.cachePlaylistDetail(detail())

        let result = app.cachedPlaylistDetail(
            for: summary(changed: "2026-08-18T13:00:00Z")
        )

        XCTAssertNil(result)
    }

    func testSongCountChangeInvalidatesCachedPlaylistDetail() {
        let app = AppState()
        app.cachePlaylistDetail(detail())

        let result = app.cachedPlaylistDetail(for: summary(count: 3))

        XCTAssertNil(result)
    }

    func testExplicitInvalidationRemovesCachedPlaylistDetail() {
        let app = AppState()
        app.cachePlaylistDetail(detail())
        app.invalidatePlaylistDetail(for: "playlist")

        XCTAssertNil(app.cachedPlaylistDetail(for: summary()))
    }

    // MARK: - Load Coordination & Shared State

    func testCachedDetailInstallsCompletedSharedState() {
        let app = AppState()
        app.cachePlaylistDetail(detail())

        app.loadPlaylistIfNeeded(summary())

        let state = app.playlistLoadState(for: summary())
        XCTAssertTrue(state?.isComplete == true)
        XCTAssertFalse(state?.isLoading == true)
        XCTAssertEqual(state?.songs.map(\.id), ["first", "second"])
    }

    func testPlaybackReadsTheSameCachedSharedState() async {
        let app = AppState()
        app.cachePlaylistDetail(detail())

        let songs = await app.playlistSongs(for: summary())

        XCTAssertEqual(songs.map(\.id), ["first", "second"])
        XCTAssertEqual(app.playlistLoadState(for: summary())?.songs, songs)
    }

    func testInvalidationCancelsSharedState() {
        let app = AppState()
        app.cachePlaylistDetail(detail())
        app.loadPlaylistIfNeeded(summary())

        app.invalidatePlaylistDetail(for: "playlist")

        XCTAssertNil(app.playlistLoadState(for: summary()))
        XCTAssertNil(app.cachedPlaylistDetail(for: summary()))
    }

    // MARK: - Disk & Memory SWR Cache

    func testAlbumDetailMemoryAndDiskCacheRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        let app = AppState()
        app.cache = cache

        let albumDetail = AlbumDetail(
            id: "al-1",
            name: "Test Album",
            artist: "Test Artist",
            song: [SubsonicSong(id: "s1", title: "Track 1")]
        )

        await app.persistAlbumDetail(albumDetail)

        // Memory hit
        let mem = await app.cachedAlbumDetail(for: "al-1")
        XCTAssertEqual(mem?.name, "Test Album")
        XCTAssertEqual(mem?.song?.count, 1)

        // Clear memory to verify disk hit
        app.library.albumDetails.removeAll()
        let disk = await app.cachedAlbumDetail(for: "al-1")
        XCTAssertEqual(disk?.name, "Test Album")
        XCTAssertEqual(disk?.song?.first?.title, "Track 1")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPlaylistDetailDiskCacheRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        let app = AppState()
        app.cache = cache

        let playlist = detail()
        await app.persistPlaylistDetailToDisk(playlist)

        let loaded = await app.cachedPlaylistDetailFromDisk(for: playlist.id)
        XCTAssertEqual(loaded?.name, "Playlist")
        XCTAssertEqual(loaded?.entry?.count, 2)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
