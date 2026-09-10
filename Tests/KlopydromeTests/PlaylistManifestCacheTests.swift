import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlaylistManifestCacheTests: XCTestCase {
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
            entry: [SubsonicSong(id: "song", title: "Song")]
        )
    }

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
}
