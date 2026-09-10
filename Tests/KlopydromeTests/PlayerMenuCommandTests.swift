import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlayerMenuCommandTests: XCTestCase {
    private func song() -> SubsonicSong {
        SubsonicSong(id: "song", title: "Song", duration: 180)
    }

    private func player() -> Player {
        let player = Player()
        player.queue = [song()]
        return player
    }

    func testAdjustVolumeClampsToSupportedRange() {
        let player = player()
        player.volume = 0.98
        player.adjustVolume(by: 0.05)
        XCTAssertEqual(player.volume, 1)

        player.volume = 0.02
        player.adjustVolume(by: -0.05)
        XCTAssertEqual(player.volume, 0)
    }

    func testStopRetainsQueueAndResetsPlaybackState() {
        let player = player()
        player.currentTime = 42
        player.duration = 180
        player.isPlaying = true
        player.isLoading = true
        player.isBuffering = true
        player.isCaching = true

        player.stop()

        XCTAssertTrue(player.hasQueue)
        XCTAssertEqual(player.currentSong?.id, "song")
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isBuffering)
        XCTAssertFalse(player.isCaching)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
    }

    func testShowingLyricsReplacesVisibleQueuePanel() {
        let app = AppState()
        app.queuePanelVisible = true
        app.showLyrics = false

        app.setPlayerPanel(.lyrics, visible: true)

        XCTAssertEqual(app.visiblePlayerPanel, .lyrics)
    }

    func testHidingInactivePanelLeavesVisiblePanelUntouched() {
        let app = AppState()
        app.queuePanelVisible = true
        app.showLyrics = true

        app.setPlayerPanel(.queue, visible: false)

        XCTAssertEqual(app.visiblePlayerPanel, .lyrics)
    }

    func testToggleReplacesVisiblePanelInsteadOfSelectingBoth() {
        let app = AppState()
        app.setPlayerPanel(.lyrics, visible: true)
        XCTAssertEqual(app.visiblePlayerPanel, .lyrics)

        app.togglePlayerPanel(.queue)

        XCTAssertEqual(app.visiblePlayerPanel, .queue)
    }

    func testTogglingVisiblePanelHidesIt() {
        let app = AppState()
        app.setPlayerPanel(.queue, visible: true)
        XCTAssertEqual(app.visiblePlayerPanel, .queue)

        app.togglePlayerPanel(.queue)

        XCTAssertEqual(app.visiblePlayerPanel, nil)
    }
}
