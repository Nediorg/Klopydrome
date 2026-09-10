import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class AutomixSettingsTests: XCTestCase {
    private func song(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    func testConfigureAutomixClampsFadeDuration() {
        let player = Player()
        player.configureAutomix(enabled: true, fadeDuration: 0)
        XCTAssertEqual(player.automixFadeDuration, 1)

        player.configureAutomix(enabled: true, fadeDuration: 13)
        XCTAssertEqual(player.automixFadeDuration, 12)
    }

    func testConfigureReplayGainClampsPreampAndReachesEngines() {
        let player = Player()
        player.configureReplayGain(mode: .album, preampDB: 20)
        XCTAssertEqual(player.replayGainMode, .album)
        XCTAssertEqual(player.replayGainPreampDB, 12)
        XCTAssertEqual(player.mpvEngine.replayGainMode, .album)
        XCTAssertEqual(player.automix.preloadedMPVEngine.replayGainMode, .album)

        player.configureReplayGain(mode: .off, preampDB: -30)
        XCTAssertEqual(player.replayGainMode, .off)
        XCTAssertEqual(player.replayGainPreampDB, -12)
        XCTAssertEqual(player.mpvEngine.replayGainMode, .off)
        XCTAssertEqual(player.automix.preloadedMPVEngine.replayGainMode, .off)
    }

    func testConfigureSilenceTrimReachesEngines() {
        let player = Player()
        player.configureSilenceTrim(mode: .strong)
        XCTAssertEqual(player.silenceTrimMode, .strong)
        XCTAssertEqual(player.mpvEngine.silenceTrimMode, .strong)
        XCTAssertEqual(player.automix.preloadedMPVEngine.silenceTrimMode, .strong)
    }

    func testDisablingAutomixKeepsPreparedSuccessorForGaplessAdvance() {
        let player = Player()
        let next = song("next")
        let sourceURL = URL(fileURLWithPath: "/tmp/next.mp3")
        player.automix.preloadedNextSong = next
        player.automix.preloadedNextSongID = next.id
        player.automix.preloadedSourceURL = sourceURL

        player.configureAutomix(enabled: false, fadeDuration: 5)

        XCTAssertFalse(player.automixEnabled)
        XCTAssertEqual(player.automix.preloadedNextSong?.id, next.id)
        XCTAssertEqual(player.automix.preloadedNextSongID, next.id)
        XCTAssertEqual(player.automix.preloadedSourceURL, sourceURL)
    }

    func testDisablingNextTrackPreloadReleasesPreparedSuccessor() {
        let player = Player()
        player.automix.preloadedNextSong = song("next")
        player.automix.preloadedNextSongID = "next"
        player.automix.preloadedSourceURL = URL(fileURLWithPath: "/tmp/next.mp3")

        player.configureNextTrackPreloading(enabled: false)

        XCTAssertFalse(player.nextTrackPreloadingEnabled)
        XCTAssertNil(player.automix.preloadedNextSong)
        XCTAssertNil(player.automix.preloadedNextSongID)
        XCTAssertNil(player.automix.preloadedSourceURL)
    }

    func testPlaybackPreferencesRoundTripThroughServerConfig() throws {
        var config = ServerConfig.empty
        config.automixEnabled = false
        config.automixFadeDuration = 8
        config.replayGainMode = .album
        config.replayGainPreampDB = -3.5
        config.silenceTrimMode = .strong
        config.nextTrackPreloadingEnabled = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

        XCTAssertFalse(decoded.effectiveAutomixEnabled)
        XCTAssertEqual(decoded.effectiveAutomixFadeDuration, 8)
        XCTAssertEqual(decoded.effectiveReplayGainMode, .album)
        XCTAssertEqual(decoded.effectiveReplayGainPreampDB, -3.5)
        XCTAssertEqual(decoded.effectiveSilenceTrimMode, .strong)
        XCTAssertFalse(decoded.effectiveNextTrackPreloadingEnabled)
    }

    func testReplayGainModeMigratesFromLegacyAutomixFlag() {
        let fresh = ServerConfig.empty
        XCTAssertEqual(fresh.effectiveReplayGainMode, .off)

        var config = ServerConfig.empty
        config.automixReplayGainEnabled = false
        XCTAssertEqual(config.effectiveReplayGainMode, .off)

        config.automixReplayGainEnabled = true
        config.replayGainMode = nil
        XCTAssertEqual(config.effectiveReplayGainMode, .track)
    }

    func testExplicitReplayGainModeWinsOverLegacyFlag() {
        var config = ServerConfig.empty
        config.automixReplayGainEnabled = false
        config.replayGainMode = .album
        XCTAssertEqual(config.effectiveReplayGainMode, .album)
    }
}
