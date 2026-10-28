import XCTest
import AppKit
import NavidromeClient
@testable import Klopydrome

@MainActor
final class MemoryOptimizationTests: XCTestCase {

    func testLibraryCacheLRUEviction() {
        let cache = LibraryCache()

        // Insert 26 album details
        for idx in 0..<26 {
            let detail = AlbumDetail(id: "album-\(idx)", name: "Album \(idx)")
            cache.albumDetails["album-\(idx)"] = detail
        }
        XCTAssertEqual(cache.albumDetails.count, 25)
        // First album (album-0) should have been evicted
        XCTAssertNil(cache.albumDetails["album-0"])
        XCTAssertNotNil(cache.albumDetails["album-25"])

        // Access album-1, then insert album-26
        cache.recordAlbumDetailAccess("album-1")
        cache.albumDetails["album-26"] = AlbumDetail(id: "album-26", name: "Album 26")
        XCTAssertEqual(cache.albumDetails.count, 25)
        // album-1 was promoted to MRU, so album-2 should be evicted instead of album-1
        XCTAssertNotNil(cache.albumDetails["album-1"])
        XCTAssertNil(cache.albumDetails["album-2"])
    }

    func testPlaylistDetailLRUEviction() {
        let cache = LibraryCache()

        for idx in 0..<26 {
            let detail = PlaylistDetail(id: "playlist-\(idx)", name: "Playlist \(idx)")
            cache.playlistDetails["playlist-\(idx)"] = detail
        }
        XCTAssertEqual(cache.playlistDetails.count, 25)
        XCTAssertNil(cache.playlistDetails["playlist-0"])
        XCTAssertNotNil(cache.playlistDetails["playlist-25"])

        // Access playlist-1, then insert playlist-26
        cache.recordPlaylistDetailAccess("playlist-1")
        cache.playlistDetails["playlist-26"] = PlaylistDetail(id: "playlist-26", name: "Playlist 26")
        XCTAssertEqual(cache.playlistDetails.count, 25)
        XCTAssertNotNil(cache.playlistDetails["playlist-1"])
        XCTAssertNil(cache.playlistDetails["playlist-2"])
    }

    func testArtistDetailLRUEviction() {
        let cache = LibraryCache()

        for idx in 0..<26 {
            let detail = ArtistDetail(id: "artist-\(idx)", name: "Artist \(idx)")
            cache.artistDetails["artist-\(idx)"] = detail
        }
        XCTAssertEqual(cache.artistDetails.count, 25)
        XCTAssertNil(cache.artistDetails["artist-0"])
        XCTAssertNotNil(cache.artistDetails["artist-25"])

        // Access artist-1, then insert artist-26
        cache.recordArtistDetailAccess("artist-1")
        cache.artistDetails["artist-26"] = ArtistDetail(id: "artist-26", name: "Artist 26")
        XCTAssertEqual(cache.artistDetails.count, 25)
        XCTAssertNotNil(cache.artistDetails["artist-1"])
        XCTAssertNil(cache.artistDetails["artist-2"])
    }

    func testAppStatePlaylistLoadStatesLRUEviction() {
        let app = AppState()

        for idx in 0..<26 {
            let summary = PlaylistSummary(id: "pl-\(idx)", name: "PL \(idx)")
            let state = PlaylistLoadState(summary: summary)
            app.playlistLoadStates["pl-\(idx)"] = state
        }
        XCTAssertEqual(app.playlistLoadStates.count, 25)
        XCTAssertNil(app.playlistLoadStates["pl-0"])
        XCTAssertNotNil(app.playlistLoadStates["pl-25"])

        // Access pl-1, then insert pl-26
        app.recordPlaylistAccess("pl-1")
        let summary26 = PlaylistSummary(id: "pl-26", name: "PL 26")
        app.playlistLoadStates["pl-26"] = PlaylistLoadState(summary: summary26)
        XCTAssertEqual(app.playlistLoadStates.count, 25)
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

    func testCoverArtStoreDownscalesLargeFallbackForSmallRequest() async {
        let store = CoverArtStore.shared
        store.clearMemoryCache()

        let coverID = "test-thumb-downscale-\(UUID().uuidString)"
        let largeKey = "\(coverID)-720"

        // Inject 720x720 dummy image into memory cache
        let largeImage = NSImage(size: NSSize(width: 720, height: 720))
        store.memory.setObject(largeImage, forKey: largeKey as NSString)
        store.lock.withLock {
            _ = store.cachedSizes[coverID, default: []].insert(720)
        }

        // Synchronous cachedImage returns the fallback directly to avoid MainActor CoreGraphics lag
        let syncThumb = store.cachedImage(coverArt: coverID, size: 40)
        XCTAssertNotNil(syncThumb)
        XCTAssertEqual(syncThumb?.size.width, 720)

        // Async image(...) performs downscaling off the main actor
        let asyncBox = await store.image(coverArt: coverID, size: 40)
        XCTAssertNotNil(asyncBox.image)
        XCTAssertLessThanOrEqual(asyncBox.image!.size.width, 240)
        XCTAssertLessThanOrEqual(asyncBox.image!.size.height, 240)

        // Verify the 240px thumbnail is now cached in memory
        let thumbKey = "\(coverID)-240"
        let cachedThumb = store.memory.object(forKey: thumbKey as NSString)
        XCTAssertNotNil(cachedThumb)

        store.clearMemoryCache()
    }
}
