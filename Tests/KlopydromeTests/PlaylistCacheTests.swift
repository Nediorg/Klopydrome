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
}
