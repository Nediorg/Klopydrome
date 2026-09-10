import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlaylistLoadCoordinatorTests: XCTestCase {
    private func summary(changed: String? = "2026-08-20T12:00:00Z", count: Int? = 2) -> PlaylistSummary {
        PlaylistSummary(
            id: "playlist",
            name: "Playlist",
            songCount: count,
            changed: changed
        )
    }

    private func detail(changed: String? = "2026-08-20T12:00:00Z", count: Int? = 2) -> PlaylistDetail {
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
