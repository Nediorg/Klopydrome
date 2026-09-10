import XCTest
@testable import Klopydrome
import NavidromeClient

final class OfflineLibraryStoreTests: XCTestCase {
    private var rootURL: URL!
    private var cache: CacheManager!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        cache = CacheManager(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        cache = nil
        rootURL = nil
    }

    func testPersistsOfflineSongMetadata() {
        let song = SubsonicSong(id: "song", title: "Song", artist: "Artist", suffix: "mp3")
        let store = OfflineLibraryStore(cache: cache)

        store.save([song])

        XCTAssertEqual(store.load(), [song])
    }

    func testClearRemovesPersistedOfflineMetadata() {
        let store = OfflineLibraryStore(cache: cache)
        store.save([SubsonicSong(id: "song", title: "Song")])

        store.clear()

        XCTAssertTrue(store.load().isEmpty)
    }
    func testPersistsOfflineLibrarySnapshot() {
        let song = SubsonicSong(id: "song", title: "Song", albumId: "album")
        let album = SubsonicAlbum(id: "album", title: "Album", songCount: 1)
        let playlist = PlaylistSummary(id: "playlist", name: "Playlist", songCount: 1)
        let albumDetail = AlbumDetail(id: "album", name: "Album", song: [song])
        let playlistDetail = PlaylistDetail(id: "playlist", name: "Playlist", entry: [song])
        let snapshot = OfflineLibrarySnapshot(
            albums: [album],
            playlists: [playlist],
            albumDetails: [album.id: albumDetail],
            playlistDetails: [playlist.id: playlistDetail]
        )
        let store = OfflineLibraryStore(cache: cache)

        store.saveSnapshot(snapshot)

        XCTAssertEqual(store.loadSnapshot(), snapshot)
    }

    func testClearRemovesOfflineLibrarySnapshot() {
        let store = OfflineLibraryStore(cache: cache)
        store.saveSnapshot(OfflineLibrarySnapshot(albums: [SubsonicAlbum(id: "album")]))

        store.clear()

        XCTAssertEqual(store.loadSnapshot(), OfflineLibrarySnapshot())
    }

}
