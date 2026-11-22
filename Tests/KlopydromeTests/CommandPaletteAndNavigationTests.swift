import XCTest
@testable import Klopydrome
import NavidromeClient

final class CommandPaletteAndNavigationTests: XCTestCase {

    @MainActor
    func testNavigationHistoryForwardAndBackward() {
        let app = AppState()
        let album1 = SubsonicAlbum(id: "alb-1", title: "Album 1")
        let album2 = SubsonicAlbum(id: "alb-2", title: "Album 2")

        XCTAssertFalse(app.canNavigateBack)
        XCTAssertFalse(app.canNavigateForward)

        app.openAlbumInLibrary(album1)
        XCTAssertTrue(app.canNavigateBack)
        XCTAssertFalse(app.canNavigateForward)
        XCTAssertEqual(app.nav.history.count, 1)

        app.openAlbumInLibrary(album2)
        XCTAssertEqual(app.nav.history.count, 2)
        XCTAssertFalse(app.canNavigateForward)

        app.navigateBack()
        XCTAssertEqual(app.nav.history.count, 1)
        XCTAssertTrue(app.canNavigateForward)
        XCTAssertEqual(app.nav.forwardHistory.count, 1)

        app.navigateForward()
        XCTAssertEqual(app.nav.history.count, 2)
        XCTAssertFalse(app.canNavigateForward)

        // New navigation should clear forward history
        app.navigateBack()
        XCTAssertTrue(app.canNavigateForward)
        let album3 = SubsonicAlbum(id: "alb-3", title: "Album 3")
        app.openAlbumInLibrary(album3)
        XCTAssertFalse(app.canNavigateForward)
        XCTAssertTrue(app.nav.forwardHistory.isEmpty)
    }

    func testSongRowSelectionKeyboardHelpers() {
        var selection = SongRowSelection()
        let song1 = SubsonicSong(id: "s1", title: "Track 1")
        let song2 = SubsonicSong(id: "s2", title: "Track 2")
        let song3 = SubsonicSong(id: "s3", title: "Track 3")
        let allSongs = [song1, song2, song3]

        // Select All
        selection.selectAll(allSongs)
        XCTAssertEqual(selection.ids.count, 3)
        XCTAssertTrue(selection.isSelected("s1"))
        XCTAssertTrue(selection.isSelected("s2"))
        XCTAssertTrue(selection.isSelected("s3"))

        // Clear
        selection.clear()
        XCTAssertTrue(selection.ids.isEmpty)

        // Move down from unselected
        let moved1 = selection.moveSelection(by: 1, in: allSongs)
        XCTAssertEqual(moved1?.id, "s1")
        XCTAssertEqual(selection.ids, ["s1"])

        // Move down
        let moved2 = selection.moveSelection(by: 1, in: allSongs)
        XCTAssertEqual(moved2?.id, "s2")
        XCTAssertEqual(selection.ids, ["s2"])

        // Move up
        let moved3 = selection.moveSelection(by: -1, in: allSongs)
        XCTAssertEqual(moved3?.id, "s1")
        XCTAssertEqual(selection.ids, ["s1"])

        // Clamped at start
        let moved4 = selection.moveSelection(by: -1, in: allSongs)
        XCTAssertEqual(moved4?.id, "s1")
        XCTAssertEqual(selection.ids, ["s1"])
    }

    @MainActor
    func testCommandPaletteLocalItemsGeneration() {
        let app = AppState()
        let items = CommandPaletteView.makeLocalItems(for: app)
        XCTAssertFalse(items.isEmpty)

        // Should include navigation and action items
        let navItems = items.filter { $0.group == .navigation }
        let actionItems = items.filter { $0.group == .actions }

        XCTAssertTrue(navItems.contains(where: { $0.id == "nav_home" }))
        XCTAssertTrue(navItems.contains(where: { $0.id == "nav_albums" }))
        XCTAssertTrue(navItems.contains(where: { $0.id == "nav_settings" }))

        XCTAssertTrue(actionItems.contains(where: { $0.id == "act_play_pause" }))
        XCTAssertTrue(actionItems.contains(where: { $0.id == "act_next" }))
        XCTAssertTrue(actionItems.contains(where: { $0.id == "act_mini_player" }))
    }
}
