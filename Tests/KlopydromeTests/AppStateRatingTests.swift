import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class AppStateRatingTests: XCTestCase {

    /// Without a client there is nothing to push and nothing to roll back:
    /// the optimistic override must stick so the UI stays consistent.
    func testToggleStarWithoutClientKeepsOverride() {
        let app = AppState()
        let song = SubsonicSong(id: "s1")
        app.toggleStar(song)
        XCTAssertTrue(app.isStarred(song))
        app.toggleStar(song)
        XCTAssertFalse(app.isStarred(song))
    }

    /// Without a client (offline session) the optimistic override still
    /// applies: the value shows instantly and sticks until the next refetch.
    func testSetRatingWithoutClientKeepsOverride() {
        let app = AppState()
        let song = SubsonicSong(id: "s1", userRating: 2)
        app.setRating(5, for: song)
        XCTAssertEqual(app.effectiveRating(for: song), 5)
    }
}
