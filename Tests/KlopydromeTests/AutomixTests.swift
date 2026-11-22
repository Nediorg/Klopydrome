import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class AutomixTests: XCTestCase {

    // MARK: - Loudness & ReplayGain

    func testDecibelConversionUsesAmplitudeScale() {
        XCTAssertEqual(AutomixLoudness.linearGain(forDecibels: 0), 1, accuracy: 0.000_001)
        XCTAssertEqual(
            AutomixLoudness.linearGain(forDecibels: -3),
            0.707_946,
            accuracy: 0.000_001
        )
    }

    func testMPVOptionsUseTrackGainAndDefaultPreamp() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .track,
            preampDB: AutomixLoudness.defaultPreampDB,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "track")
        XCTAssertEqual(options["replaygain-preamp"], "0")
        XCTAssertEqual(options["replaygain-fallback"], "0")
        XCTAssertEqual(options["replaygain-clip"], "no")
        XCTAssertNil(options["af"])
    }

    func testMPVOptionsHonorAlbumModeAndPreamp() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .album,
            preampDB: -3.5,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "album")
        XCTAssertEqual(options["replaygain-preamp"], "-3.5")
        XCTAssertEqual(options["replaygain-fallback"], "-3.5")
        XCTAssertNil(options["af"])
    }

    func testMPVOptionsDisableGainOmitsClip() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .off,
            preampDB: 0,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "no")
        XCTAssertEqual(options["replaygain-preamp"], "0")
        XCTAssertEqual(options["replaygain-fallback"], "0")
    }

    func testPreampClampsToSupportedRange() {
        XCTAssertEqual(AutomixLoudness.clampPreamp(20), 12)
        XCTAssertEqual(AutomixLoudness.clampPreamp(-20), -12)
        XCTAssertEqual(AutomixLoudness.clampPreamp(-3), -3)
    }

    func testMPVOptionsAttachSilenceTrimFilter() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .track,
            preampDB: -3,
            silenceTrimMode: .strong
        ))
        XCTAssertEqual(options["af"], SilenceTrimMode.strong.mpvAudioFilterOption())
    }

    func testSilenceTrimFilterOptionTrimsOnlyTrackEnd() {
        XCTAssertNil(SilenceTrimMode.off.mpvAudioFilterOption())
        XCTAssertNotNil(SilenceTrimMode.light.mpvAudioFilterOption())
        XCTAssertNotNil(SilenceTrimMode.strong.mpvAudioFilterOption())
        for mode in [SilenceTrimMode.light, .strong] {
            let option = mode.mpvAudioFilterOption()
            XCTAssertTrue(option?.hasPrefix("lavfi=[silenceremove=") ?? false)
            XCTAssertTrue(option?.contains("stop_periods=1") ?? false)
            XCTAssertTrue(option?.hasSuffix("]") ?? false)
        }
    }

    // MARK: - Player Configuration

    private func mockSong(_ id: String) -> SubsonicSong {
        SubsonicSong(id: id, title: id, duration: 180)
    }

    func testConfigureReplayGainClampsPreampAndReachesEngine() {
        let player = Player()
        player.configureReplayGain(mode: .album, preampDB: 20)
        XCTAssertEqual(player.replayGainMode, .album)
        XCTAssertEqual(player.replayGainPreampDB, 12)
        XCTAssertEqual(player.mpvEngine.replayGainMode, .album)

        player.configureReplayGain(mode: .off, preampDB: -30)
        XCTAssertEqual(player.replayGainMode, .off)
        XCTAssertEqual(player.replayGainPreampDB, -12)
        XCTAssertEqual(player.mpvEngine.replayGainMode, .off)
    }

    func testConfigureSilenceTrimReachesEngine() {
        let player = Player()
        player.configureSilenceTrim(mode: .strong)
        XCTAssertEqual(player.silenceTrimMode, .strong)
        XCTAssertEqual(player.mpvEngine.silenceTrimMode, .strong)
    }

    func testDisablingNextTrackPreloadReleasesPreparedSuccessor() {
        let player = Player()
        player.preloadedNextSong = mockSong("next")
        player.preloadedNextSongID = "next"
        player.preloadedSourceURL = URL(fileURLWithPath: "/tmp/next.mp3")

        player.configureNextTrackPreloading(enabled: false)

        XCTAssertFalse(player.nextTrackPreloadingEnabled)
        XCTAssertNil(player.preloadedNextSong)
        XCTAssertNil(player.preloadedNextSongID)
        XCTAssertNil(player.preloadedSourceURL)
    }

    func testPlaybackPreferencesRoundTripThroughServerConfig() throws {
        var config = ServerConfig.empty
        config.replayGainMode = .album
        config.replayGainPreampDB = -3.5
        config.silenceTrimMode = .strong
        config.nextTrackPreloadingEnabled = false

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

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
