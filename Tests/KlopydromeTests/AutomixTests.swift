import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class AutomixTests: XCTestCase {

    // MARK: - Crossfade Curves

    func testEqualPowerGainsStartWithOutgoingTrackOnly() {
        let gains = AutomixCrossfade.gains(progress: 0)

        XCTAssertEqual(gains.outgoing, 1, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 0, accuracy: 0.000_1)
    }

    func testEqualPowerGainsPreserveEnergyAtMidpoint() {
        let gains = AutomixCrossfade.gains(progress: 0.5)

        XCTAssertEqual(gains.outgoing, 0.707_106_8, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 0.707_106_8, accuracy: 0.000_1)
    }

    func testEqualPowerGainsEndWithIncomingTrackOnly() {
        let gains = AutomixCrossfade.gains(progress: 1)

        XCTAssertEqual(gains.outgoing, 0, accuracy: 0.000_1)
        XCTAssertEqual(gains.incoming, 1, accuracy: 0.000_1)
    }

    func testGainsClampProgressOutsideTransition() {
        XCTAssertEqual(AutomixCrossfade.gains(progress: -1).outgoing, 1)
        XCTAssertEqual(AutomixCrossfade.gains(progress: 2).incoming, 1)
    }

    // MARK: - Loudness & ReplayGain

    func testDecibelConversionUsesAmplitudeScale() {
        XCTAssertEqual(AutomixLoudness.linearGain(forDecibels: 0), 1, accuracy: 0.000_001)
        XCTAssertEqual(
            AutomixLoudness.linearGain(forDecibels: AutomixLoudness.crossfadeHeadroomDB),
            0.707_946,
            accuracy: 0.000_001
        )
    }

    func testMPVOptionsUseTrackGainAndConservativeHeadroom() {
        let options = Dictionary(uniqueKeysWithValues: AutomixLoudness.mpvOptions(
            replayGainMode: .track,
            preampDB: AutomixLoudness.crossfadeHeadroomDB,
            silenceTrimMode: .off
        ))
        XCTAssertEqual(options["replaygain"], "track")
        XCTAssertEqual(options["replaygain-preamp"], "-3")
        XCTAssertEqual(options["replaygain-fallback"], "-3")
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

    // MARK: - Transition Planning

    private func makeProfile(
        leading: [Float] = [],
        trailing: [Float] = [],
        frameDuration: Double = 0.1
    ) -> AutomixEdgeProfile {
        AutomixEdgeProfile(
            frameDuration: frameDuration,
            leadingDBFS: leading,
            trailingDBFS: trailing
        )
    }

    func testSilenceDefinesFadeDurationAndIncomingLeadIn() {
        let outgoing = makeProfile(trailing: Array(repeating: -12, count: 80) + Array(repeating: -52, count: 40))
        let incoming = makeProfile(leading: Array(repeating: -52, count: 30) + Array(repeating: -12, count: 90))

        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: outgoing,
            incoming: incoming
        )

        XCTAssertEqual(plan.basis, .silence)
        XCTAssertEqual(plan.fadeDuration, 4, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 196, accuracy: 0.001)
        XCTAssertEqual(plan.incomingLeadIn, 3, accuracy: 0.001)
    }

    func testOnsetRefinesFallbackWhenNoSilenceExists() {
        var tail = Array(repeating: Float(-20), count: 120)
        tail[68] = -30
        tail[69] = -1
        tail[70] = -30
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: makeProfile(trailing: tail),
            incoming: makeProfile(leading: Array(repeating: -20, count: 120))
        )

        XCTAssertEqual(plan.basis, .onset)
        XCTAssertGreaterThanOrEqual(plan.fadeDuration, AutomixTransitionPlanner.minimumFade)
        XCTAssertLessThanOrEqual(plan.fadeDuration, AutomixTransitionPlanner.maximumFade)
    }

    func testFallbackIsSafeWithoutDecodedProfiles() {
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: nil,
            incoming: nil
        )

        XCTAssertEqual(plan.basis, .fallback)
        XCTAssertEqual(plan.fadeDuration, AutomixTransitionPlanner.defaultFade, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 195, accuracy: 0.001)
    }

    func testPreferredFadeDurationOverridesFallback() {
        let plan = AutomixTransitionPlanner.plan(
            currentDuration: 200,
            outgoing: nil,
            incoming: nil,
            preferredFadeDuration: 9
        )

        XCTAssertEqual(plan.basis, .fallback)
        XCTAssertEqual(plan.fadeDuration, 9, accuracy: 0.001)
        XCTAssertEqual(plan.fadeOutStart, 191, accuracy: 0.001)
    }

    // MARK: - Settings & Propagation

    private func mockSong(_ id: String) -> SubsonicSong {
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
        let next = mockSong("next")
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
        player.automix.preloadedNextSong = mockSong("next")
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

    // MARK: - Crossfade Status

    func testDisplaySongSwitchesToIncomingTrackWhenCrossfadeStarts() {
        let player = Player()
        player.queue = [mockSong("outgoing"), mockSong("incoming")]
        player.currentIndex = 0
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "incoming",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(player.currentSong?.id, "outgoing")
        XCTAssertEqual(player.displaySong?.id, "incoming")

        player.isCrossfading = false
        XCTAssertEqual(player.displaySong?.id, "outgoing")
    }

    func testStatusIsAbsentWithoutActiveCrossfade() {
        let player = Player()

        XCTAssertNil(player.crossfadeRemainingTime)
        XCTAssertNil(player.crossfadeStatusText)
    }

    func testPreparedTransitionDoesNotShowStatusBeforeOverlapStarts() {
        let player = Player()
        player.currentTime = 12
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.crossfadeStatusText)
    }

    func testStatusShowsRemainingOverlapTime() {
        let player = Player()
        player.currentTime = 12
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(try XCTUnwrap(player.crossfadeRemainingTime), 3, accuracy: 0.001)
        XCTAssertEqual(player.crossfadeStatusText, "Crossfade · 3 s")
    }

    func testStatusRoundsPartialSecondUpForTheListener() {
        let player = Player()
        player.currentTime = 12.2
        player.isCrossfading = true
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: "next",
            startTime: 10,
            duration: 5
        )

        XCTAssertEqual(player.crossfadeStatusText, "Crossfade · 3 s")
    }
}
