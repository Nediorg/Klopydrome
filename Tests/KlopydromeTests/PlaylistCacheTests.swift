import XCTest
@testable import Klopydrome
import NavidromeClient
import Observation
import os

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

    func testArtistDetailMemoryAndDiskCacheRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        let app = AppState()
        app.cache = cache

        let artistDetail = ArtistDetail(
            id: "ar-1",
            name: "Test Artist",
            coverArt: "cover-1",
            albumCount: 2,
            album: [SubsonicAlbum(id: "al-1", name: "Album 1")]
        )

        await app.persistArtistDetail(artistDetail)

        // Memory hit
        let mem = await app.cachedArtistDetail(for: "ar-1")
        XCTAssertEqual(mem?.name, "Test Artist")
        XCTAssertEqual(mem?.albumCount, 2)

        // Clear memory to verify disk hit
        app.library.artistDetails.removeAll()
        let disk = await app.cachedArtistDetail(for: "ar-1")
        XCTAssertEqual(disk?.name, "Test Artist")
        XCTAssertEqual(disk?.album?.first?.id, "al-1")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFavoritesSongsDiskCacheRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CacheManager(rootURL: tempDir)
        let app = AppState()
        app.cache = cache

        app.library.favoritesSongs = [
            SubsonicSong(id: "fav-1", title: "Favorite Song 1"),
            SubsonicSong(id: "fav-2", title: "Favorite Song 2")
        ]

        await app.persistFavoritesToDisk()

        // Clear memory
        app.library.favoritesSongs.removeAll()

        // Restore from disk
        await app.restoreLibraryFromDiskCache()
        XCTAssertEqual(app.library.favoritesSongs.count, 2)
        XCTAssertEqual(app.library.favoritesSongs.first?.title, "Favorite Song 1")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCancelPlaylistTaskPreservesLoadedSongs() {
        let app = AppState()
        app.cachePlaylistDetail(detail())
        app.loadPlaylistIfNeeded(summary())

        XCTAssertEqual(app.playlistLoadState(for: summary())?.songs.count, 2)

        app.cancelPlaylistTask(for: "playlist")

        XCTAssertEqual(app.playlistLoadState(for: summary())?.songs.count, 2)
        XCTAssertNil(app.playlistLoadTasks["playlist"])
    }

    func testMatchingManifestSkipsTaskSpawn() {
        let app = AppState()
        app.cachePlaylistDetail(detail())
        app.loadPlaylistIfNeeded(summary())

        let taskBefore = app.playlistLoadTasks["playlist"]
        app.loadPlaylistIfNeeded(summary())
        let taskAfter = app.playlistLoadTasks["playlist"]

        XCTAssertNil(taskBefore)
        XCTAssertNil(taskAfter)
    }

    func testManifestMismatchDoesNotMatchCompletedState() {
        let app = AppState()
        app.cachePlaylistDetail(detail())
        app.loadPlaylistIfNeeded(summary())

        let updated = summary(changed: "2026-08-18T15:00:00Z")
        let matches = app.playlistLoadState(for: updated)?.matches(updated) ?? false
        XCTAssertFalse(matches)
    }

    func testCancelPlaylistTaskResetsIsSyncing() {
        let app = AppState()
        var state = PlaylistLoadState(summary: summary())
        state.isSyncing = true
        app.playlistLoadStates["playlist"] = state

        app.cancelPlaylistTask(for: "playlist")

        XCTAssertFalse(app.playlistLoadStates["playlist"]?.isSyncing ?? true)
    }

    func testPlaylistLoadStateGetterIsPureAndIdempotent() {
        let app = AppState()
        let playlist = summary()
        var state = PlaylistLoadState(summary: playlist)
        state.isComplete = true
        app.playlistLoadStates[playlist.id] = state

        let notificationCount = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = app.playlistLoadState(for: playlist)
        } onChange: {
            notificationCount.withLock { $0 += 1 }
        }

        // Reading state multiple times must NOT mutate state or trigger Observation notifications
        _ = app.playlistLoadState(for: playlist)
        _ = app.playlistLoadState(for: playlist)
        _ = app.playlistLoadState(for: playlist)

        let finalCount = notificationCount.withLock { $0 }
        XCTAssertEqual(
            finalCount,
            0,
            "Repeated reads of playlistLoadState must be pure and not trigger Observation onChange"
        )
    }

    func testCachedPlaylistDetailGetterIsPureAndIdempotent() {
        let app = AppState()
        let playlist = summary()
        let detail = PlaylistDetail(id: playlist.id, name: playlist.name, songCount: playlist.songCount, entry: [])
        app.cachePlaylistDetail(detail)

        let notificationCount = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = app.cachedPlaylistDetail(for: playlist)
        } onChange: {
            notificationCount.withLock { $0 += 1 }
        }

        // Multiple reads must not mutate LRU order or fire observation onChange
        _ = app.cachedPlaylistDetail(for: playlist)
        _ = app.cachedPlaylistDetail(for: playlist)
        _ = app.cachedPlaylistDetail(for: playlist)

        let finalCount = notificationCount.withLock { $0 }
        XCTAssertEqual(
            finalCount,
            0,
            "Repeated reads of cachedPlaylistDetail must be pure and not trigger Observation onChange"
        )
    }
}
