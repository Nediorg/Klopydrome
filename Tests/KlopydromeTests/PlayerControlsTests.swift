import AVFoundation
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

    // MARK: - AVPlayer Error Formatting

    func testFormatAVPlayerErrorIncludesErrorCodes() {
        let error = NSError(domain: AVFoundationErrorDomain, code: -11850)
        let formatted = Player.formatAVPlayerError(error)
        XCTAssertTrue(formatted.contains("AVErrorServerIncorrectlyConfigured"))
        XCTAssertTrue(formatted.contains("-11850"))
    }

    func testFormatAVPlayerErrorWithUnderlyingError() {
        let underlying = NSError(domain: "CoreMediaErrorDomain", code: -12884)
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11850,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let formatted = Player.formatAVPlayerError(error)
        XCTAssertTrue(formatted.contains("-11850"))
        XCTAssertTrue(formatted.contains("CoreMediaErrorDomain"))
        XCTAssertTrue(formatted.contains("-12884"))
    }

    func testFormatAVPlayerErrorNilFallback() {
        let formatted = Player.formatAVPlayerError(nil)
        XCTAssertEqual(formatted, L10n.text("format.player.unavailable"))
    }

    // MARK: - Seeking Safety & In-Flight EOF Guards

    func testSeekClampsPastDurationToAvoidEOF() {
        let player = makePlayer()
        player.duration = 180.0
        player.seek(to: 200.0)
        XCTAssertEqual(player.currentTime, 179.5, accuracy: 0.001)
        XCTAssertEqual(player.heldSeekTarget ?? 0, 179.5, accuracy: 0.001)
        XCTAssertTrue(player.isSeekInFlight)
    }

    func testPromotePreloadedTrackOnManualNextUsesSkipToAppendedTrack() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = SubsonicSong(id: "s1", title: "Song 1", duration: 180)
        let song2 = SubsonicSong(id: "s2", title: "Song 2", duration: 200)
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.preloadedNextSongID = "s2"
        player.mpvEngine.setHasAppendedTrackForTesting(true, url: URL(fileURLWithPath: "/tmp/s2.mp3"))

        let promoted = player.promotePreloadedMPVTrack(for: song2, autoPlay: true)

        XCTAssertTrue(promoted)
        XCTAssertFalse(player.mpvEngine.hasAppendedTrack)
        XCTAssertFalse(player.mpvEngine.didAdvanceToAppendedTrack)
    }

    func testSyncPreloadedNextWithQueueResetsWhenNextSongChanges() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = SubsonicSong(id: "s1", title: "Song 1", duration: 180)
        let song2 = SubsonicSong(id: "s2", title: "Song 2", duration: 200)
        let song3 = SubsonicSong(id: "s3", title: "Song 3", duration: 220)
        player.queue = [song1, song2, song3]
        player.currentIndex = 0
        player.preloadedNextSongID = "s2"

        player.remove(at: 1)

        XCTAssertNil(player.preloadedNextSongID)
    }

    func testTrackDurationFallsBackToMetadataWhenEngineDurationIsZero() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song = SubsonicSong(id: "s1", title: "Song 1", duration: 180)
        player.queue = [song]
        player.currentIndex = 0
        player.currentSourceURL = URL(fileURLWithPath: "/tmp/fake.opus")

        XCTAssertEqual(player.trackDuration, 180.0)
    }

    func testTrackDurationPrefersEngineDurationWhenAccurate() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song = SubsonicSong(id: "s1", title: "Song 1", duration: 180)
        player.queue = [song]
        player.currentIndex = 0

        player.mpvEngine.setDuration(179.8)

        XCTAssertEqual(player.trackDuration, 179.8, accuracy: 0.001)
    }
}
