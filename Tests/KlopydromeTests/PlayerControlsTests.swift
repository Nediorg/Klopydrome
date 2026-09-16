import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class PlayerControlsTests: XCTestCase {

    // MARK: - Playback Volume & Stop Commands

    private func mockSong() -> SubsonicSong {
        SubsonicSong(id: "song", title: "Song", duration: 180)
    }

    private func makePlayer() -> Player {
        let player = Player()
        player.queue = [mockSong()]
        return player
    }

    func testAdjustVolumeClampsToSupportedRange() {
        let player = makePlayer()
        player.volume = 0.98
        player.adjustVolume(by: 0.05)
        XCTAssertEqual(player.volume, 1)

        player.volume = 0.02
        player.adjustVolume(by: -0.05)
        XCTAssertEqual(player.volume, 0)
    }

    func testStopRetainsQueueAndResetsPlaybackState() {
        let player = makePlayer()
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

    // MARK: - Panel Exclusivity

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

    // MARK: - Exit Preferences Persistence

    func testMissingPreferencesUseSafeDefaults() {
        let defaults = UserDefaults(suiteName: "PlayerControlsExitPrefsTests")!
        defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests")
        defer { defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests") }

        let preferences = PlaybackExitPreferences.load(from: defaults)

        XCTAssertEqual(preferences.volume, 1, accuracy: 0.0001)
        XCTAssertFalse(preferences.shuffleEnabled)
    }

    func testSaveRoundTripsVolumeAndShuffle() {
        let defaults = UserDefaults(suiteName: "PlayerControlsExitPrefsTests")!
        defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests")
        defer { defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests") }

        PlaybackExitPreferences(volume: 0.35, shuffleEnabled: true).save(to: defaults)

        let preferences = PlaybackExitPreferences.load(from: defaults)
        XCTAssertEqual(preferences.volume, 0.35, accuracy: 0.0001)
        XCTAssertTrue(preferences.shuffleEnabled)
    }

    func testInvalidStoredVolumeIsClamped() {
        let defaults = UserDefaults(suiteName: "PlayerControlsExitPrefsTests")!
        defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests")
        defer { defaults.removePersistentDomain(forName: "PlayerControlsExitPrefsTests") }

        defaults.set(4.0, forKey: PlaybackExitPreferences.volumeKey)
        defaults.set(true, forKey: PlaybackExitPreferences.shuffleEnabledKey)

        let preferences = PlaybackExitPreferences.load(from: defaults)
        XCTAssertEqual(preferences.volume, 1, accuracy: 0.0001)
        XCTAssertTrue(preferences.shuffleEnabled)
    }
}
