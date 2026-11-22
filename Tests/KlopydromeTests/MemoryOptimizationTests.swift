import XCTest
import AppKit
import NavidromeClient
@testable import Klopydrome

@MainActor
final class MemoryOptimizationTests: XCTestCase {

    func testLibraryCacheLRUEviction() {
        let cache = LibraryCache()

        for idx in 0..<13 {
            let detail = AlbumDetail(id: "album-\(idx)", name: "Album \(idx)")
            cache.albumDetails["album-\(idx)"] = detail
        }
        XCTAssertEqual(cache.albumDetails.count, 12)
        XCTAssertNil(cache.albumDetails["album-0"])
        XCTAssertNotNil(cache.albumDetails["album-12"])

        cache.recordAlbumDetailAccess("album-1")
        cache.albumDetails["album-13"] = AlbumDetail(id: "album-13", name: "Album 13")
        XCTAssertEqual(cache.albumDetails.count, 12)
        XCTAssertNotNil(cache.albumDetails["album-1"])
        XCTAssertNil(cache.albumDetails["album-2"])
    }

    func testPlaylistDetailLRUEviction() {
        let cache = LibraryCache()

        for idx in 0..<13 {
            let detail = PlaylistDetail(id: "playlist-\(idx)", name: "Playlist \(idx)")
            cache.playlistDetails["playlist-\(idx)"] = detail
        }
        XCTAssertEqual(cache.playlistDetails.count, 12)
        XCTAssertNil(cache.playlistDetails["playlist-0"])
        XCTAssertNotNil(cache.playlistDetails["playlist-12"])

        cache.recordPlaylistDetailAccess("playlist-1")
        cache.playlistDetails["playlist-13"] = PlaylistDetail(id: "playlist-13", name: "Playlist 13")
        XCTAssertEqual(cache.playlistDetails.count, 12)
        XCTAssertNotNil(cache.playlistDetails["playlist-1"])
        XCTAssertNil(cache.playlistDetails["playlist-2"])
    }

    func testArtistDetailLRUEviction() {
        let cache = LibraryCache()

        for idx in 0..<13 {
            let detail = ArtistDetail(id: "artist-\(idx)", name: "Artist \(idx)")
            cache.artistDetails["artist-\(idx)"] = detail
        }
        XCTAssertEqual(cache.artistDetails.count, 12)
        XCTAssertNil(cache.artistDetails["artist-0"])
        XCTAssertNotNil(cache.artistDetails["artist-12"])

        cache.recordArtistDetailAccess("artist-1")
        cache.artistDetails["artist-13"] = ArtistDetail(id: "artist-13", name: "Artist 13")
        XCTAssertEqual(cache.artistDetails.count, 12)
        XCTAssertNotNil(cache.artistDetails["artist-1"])
        XCTAssertNil(cache.artistDetails["artist-2"])
    }

    func testAppStatePlaylistLoadStatesLRUEviction() {
        let app = AppState()

        for idx in 0..<11 {
            let summary = PlaylistSummary(id: "pl-\(idx)", name: "PL \(idx)")
            let state = PlaylistLoadState(summary: summary)
            app.playlistLoadStates["pl-\(idx)"] = state
        }
        XCTAssertEqual(app.playlistLoadStates.count, 10)
        XCTAssertNil(app.playlistLoadStates["pl-0"])
        XCTAssertNotNil(app.playlistLoadStates["pl-10"])

        app.recordPlaylistAccess("pl-1")
        let summary11 = PlaylistSummary(id: "pl-11", name: "PL 11")
        app.playlistLoadStates["pl-11"] = PlaylistLoadState(summary: summary11)
        XCTAssertEqual(app.playlistLoadStates.count, 10)
        XCTAssertNotNil(app.playlistLoadStates["pl-1"])
        XCTAssertNil(app.playlistLoadStates["pl-2"])
    }

    func testHandleMemoryPressureClearsAllCaches() {
        let app = AppState()
        app.library.albumDetails["a1"] = AlbumDetail(id: "a1", name: "Album 1")
        app.library.artistDetails["art1"] = ArtistDetail(id: "art1", name: "Artist 1")
        app.library.playlistDetails["p1"] = PlaylistDetail(id: "p1", name: "PL 1")
        app.playlistLoadStates["p1"] = PlaylistLoadState(summary: PlaylistSummary(id: "p1", name: "PL 1"))
        app.library.songs = [SubsonicSong(id: "s1", title: "Song 1")]
        app.library.songsLoaded = true

        app.handleMemoryPressure()

        XCTAssertTrue(app.library.albumDetails.isEmpty)
        XCTAssertTrue(app.library.artistDetails.isEmpty)
        XCTAssertTrue(app.library.playlistDetails.isEmpty)
        XCTAssertTrue(app.playlistLoadStates.isEmpty)
        XCTAssertTrue(app.library.songs.isEmpty)
        XCTAssertFalse(app.library.songsLoaded)
    }

    func testLazyAVPlayerInitialization() {
        let player = Player()
        XCTAssertNil(player.avPlayer)
        XCTAssertEqual(player.engineKind, .mpv)

        let avp = player.ensureAVPlayer()
        XCTAssertNotNil(player.avPlayer)
        XCTAssertTrue(player.avPlayer === avp)
    }

    func testCoverArtStoreReusesLargerCachedImageWithoutDuplicateCopy() async {
        let store = CoverArtStore.shared
        store.clearMemoryCache()

        let coverID = "test-thumb-reuse-\(UUID().uuidString)"
        let largeKey = "\(coverID)-720"

        let largeImage = NSImage(size: NSSize(width: 720, height: 720))
        store.memory.setObject(largeImage, forKey: largeKey as NSString)
        store.lock.withLock {
            _ = store.cachedSizes[coverID, default: []].insert(720)
        }

        let syncThumb = store.cachedImage(coverArt: coverID, size: 40)
        XCTAssertTrue(syncThumb === largeImage)

        let asyncBox = await store.image(coverArt: coverID, size: 40)
        XCTAssertTrue(asyncBox.image === largeImage)

        let thumbKey = "\(coverID)-240"
        XCTAssertNil(store.memory.object(forKey: thumbKey as NSString))

        store.clearMemoryCache()
    }

    func testMiniPlayerVariableBlurCacheClear() {
        let cache = MiniPlayerVariableBlurCache.shared
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 400,
            bitsPerPixel: 32
        )!
        let dummy = NSImage(size: NSSize(width: 100, height: 100))
        dummy.addRepresentation(rep)

        let rendered = cache.renderBlur(coverArt: "test-blur", source: dummy, targetSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(rendered)
        XCTAssertEqual(rendered?.size.width, 100)
        XCTAssertEqual(rendered?.size.height, 100)
        XCTAssertNotNil(cache.cached(coverArt: "test-blur", targetSize: CGSize(width: 100, height: 100)))

        cache.clear()
        XCTAssertNil(cache.cached(coverArt: "test-blur", targetSize: CGSize(width: 100, height: 100)))
    }

    func testCacheManagerClearInMemoryCachesDropsDiscography() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheClearMem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = CacheManager(rootURL: tempDir)
        await cache.cacheDiscography([SubsonicSong(id: "s-1", title: "Track")], for: "artist-1")
        let cachedBefore = await cache.cachedDiscography(for: "artist-1")
        XCTAssertEqual(cachedBefore?.count, 1)

        await cache.clearInMemoryCaches()
        let cachedAfter = await cache.cachedDiscography(for: "artist-1")
        XCTAssertNil(cachedAfter)
    }

    func testShuffleStateSingleBackupQueue() {
        let player = Player()
        let songs = (1...5).map { idx in
            SubsonicSong(id: "s-\(idx)", title: "Song \(idx)")
        }
        player.queue = songs
        player.currentIndex = 0

        player.setShuffleEnabled(true)
        XCTAssertTrue(player.shuffle)
        XCTAssertEqual(player.shuffleState.originalQueue.count, 5)

        player.setShuffleEnabled(false)
        XCTAssertFalse(player.shuffle)
        XCTAssertTrue(player.shuffleState.originalQueue.isEmpty)
        XCTAssertEqual(player.queue.map(\.id), songs.map(\.id))
    }

    func testRowHoverManagerPrunesOffscreenStates() {
        let manager = RowHoverManager()
        let keptState = manager.state(for: "s-2")
        let hoveredState = manager.state(for: "s-3")
        _ = manager.state(for: "s-1")
        _ = manager.state(for: "s-4")
        manager.setHovered(id: "s-3")
        XCTAssertEqual(manager.stateCount, 4)

        manager.prune(keeping: ["s-2"])

        XCTAssertEqual(manager.stateCount, 2)
        XCTAssertTrue(manager.state(for: "s-2") === keptState)
        XCTAssertTrue(manager.state(for: "s-3") === hoveredState)
        XCTAssertTrue(hoveredState.isHovered)
    }
}
