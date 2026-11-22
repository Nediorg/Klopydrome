import AppKit
import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class CrossfadeTests: XCTestCase {

    private func mockSong(
        _ id: String,
        albumId: String? = nil,
        album: String? = nil,
        duration: Int = 180
    ) -> SubsonicSong {
        SubsonicSong(id: id, title: id, album: album, duration: duration, albumId: albumId)
    }

    func testGainsEqualPowerAndClamping() {
        let start = CrossfadeMath.gains(progress: 0)
        XCTAssertEqual(start.outgoing, 1, accuracy: 0.0001)
        XCTAssertEqual(start.incoming, 0, accuracy: 0.0001)

        let mid = CrossfadeMath.gains(progress: 0.5)
        let expectedMid = Float(sqrt(0.5))
        XCTAssertEqual(mid.outgoing, expectedMid, accuracy: 0.0001)
        XCTAssertEqual(mid.incoming, expectedMid, accuracy: 0.0001)

        let end = CrossfadeMath.gains(progress: 1)
        XCTAssertEqual(end.outgoing, 0, accuracy: 0.0001)
        XCTAssertEqual(end.incoming, 1, accuracy: 0.0001)

        XCTAssertEqual(CrossfadeMath.gains(progress: -0.5), start)
        XCTAssertEqual(CrossfadeMath.gains(progress: 1.5), end)
    }

    func testStepProgressIncrementsOncePerSecond() {
        XCTAssertEqual(CrossfadeMath.stepProgress(elapsed: 0.0, duration: 5.0), 0.2, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.stepProgress(elapsed: 0.9, duration: 5.0), 0.2, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.stepProgress(elapsed: 1.0, duration: 5.0), 0.4, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.stepProgress(elapsed: 4.0, duration: 5.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.stepProgress(elapsed: 6.0, duration: 5.0), 1.0, accuracy: 0.0001)
    }

    func testProgressClampingAndZeroDuration() {
        XCTAssertEqual(CrossfadeMath.progress(elapsed: -1.0, duration: 5.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.progress(elapsed: 0.0, duration: 5.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.progress(elapsed: 2.5, duration: 5.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.progress(elapsed: 6.0, duration: 5.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.progress(elapsed: 0.0, duration: 0.0), 1.0, accuracy: 0.0001)
    }

    func testCrossfadeSymbolSupportsVariableValue() {
        let image = NSImage(
            systemSymbolName: "circle.dotted.circle",
            variableValue: 0.51,
            accessibilityDescription: nil
        )
        XCTAssertNotNil(image)
    }

    func testClampDuration() {
        XCTAssertEqual(CrossfadeMath.clampDuration(0), 1)
        XCTAssertEqual(CrossfadeMath.clampDuration(20), 12)
        XCTAssertEqual(CrossfadeMath.clampDuration(6), 6)
    }

    func testEffectiveDurationMatchesRemainingWhenStartedLate() {
        XCTAssertEqual(CrossfadeMath.effectiveDuration(configured: 5.0, remaining: 5.0), 5.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.effectiveDuration(configured: 5.0, remaining: 3.75), 3.75, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.effectiveDuration(configured: 5.0, remaining: 0.05), 0.25, accuracy: 0.0001)
    }

    func testTrackProgressFollowsTrackARemainingTime() {
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: 5.0, crossfadeDuration: 5.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: 3.75, crossfadeDuration: 5.0), 0.25, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: 2.5, crossfadeDuration: 5.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: 0.0, crossfadeDuration: 5.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: 7.0, crossfadeDuration: 5.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.trackProgress(remaining: -1.0, crossfadeDuration: 5.0), 1.0, accuracy: 0.0001)
    }

    func testFadeOpacityBounds() {
        XCTAssertEqual(CrossfadeMath.fadeOpacity(elapsed: 0.0, duration: 0.25, fadingIn: true), 0.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.fadeOpacity(elapsed: 0.25, duration: 0.25, fadingIn: true), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.fadeOpacity(elapsed: 0.0, duration: 0.30, fadingIn: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CrossfadeMath.fadeOpacity(elapsed: 0.30, duration: 0.30, fadingIn: false), 0.0, accuracy: 0.0001)
    }

    func testPlayerCrossfadeTrackProgressUsesTrackATime() {
        let player = Player()
        let first = mockSong("1", duration: 180)
        let second = mockSong("2", duration: 180)
        player.queue = [first, second]
        player.currentIndex = 0
        player.configureCrossfade(enabled: true, fadeDuration: 5, applyToAlbums: true)
        player.duration = 180
        player.mpvEngine.duration = 180
        player.currentTime = 177.5
        player.isPlaying = true
        player.isCrossfading = true
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 2.5)

        let progress = player.crossfadeTrackProgress(at: 100)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testShouldCrossfadeRespectsAlbumSuppressionAndState() {
        let player = Player()
        let song1 = mockSong("1", albumId: "a1", album: "Album A")
        let song2SameAlbum = mockSong("2", albumId: "a1", album: "Album A")
        let song3DifferentAlbum = mockSong("3", albumId: "a2", album: "Album B")
        player.queue = [song1, song2SameAlbum, song3DifferentAlbum]
        player.currentIndex = 0
        player.engineKind = .mpv
        player.configureCrossfade(enabled: true, fadeDuration: 5, applyToAlbums: false)

        XCTAssertFalse(player.shouldCrossfade(to: song2SameAlbum))
        XCTAssertTrue(player.shouldCrossfade(to: song3DifferentAlbum))
        XCTAssertFalse(player.shouldCrossfade(to: song1))

        player.configureCrossfade(enabled: true, fadeDuration: 5, applyToAlbums: true)
        XCTAssertTrue(player.shouldCrossfade(to: song2SameAlbum))

        player.setRepeatMode(.one)
        XCTAssertFalse(player.shouldCrossfade(to: song3DifferentAlbum))
        player.setRepeatMode(.off)

        player.configureCrossfade(enabled: false, fadeDuration: 5, applyToAlbums: true)
        XCTAssertFalse(player.shouldCrossfade(to: song3DifferentAlbum))
    }

    func testDisplaySongSwitchesToUpcomingDuringCrossfade() {
        let player = Player()
        let first = mockSong("1")
        let second = mockSong("2")
        player.queue = [first, second]
        player.currentIndex = 0

        XCTAssertEqual(player.displaySong?.id, "1")
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 5)
        player.isCrossfading = true
        XCTAssertEqual(player.displaySong?.id, "2")
        player.isCrossfading = false
        player.activeCrossfade = nil
        XCTAssertEqual(player.displaySong?.id, "1")
    }

    func testCancelCrossfadeResetsActiveStateOnStopAndRepeatOne() {
        let player = Player()
        let first = mockSong("1")
        let second = mockSong("2")
        player.queue = [first, second]
        player.currentIndex = 0
        player.isCrossfading = true
        player.crossfadeStepProgress = 0.6
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 5)

        player.setRepeatMode(.one)
        XCTAssertFalse(player.isCrossfading)
        XCTAssertEqual(player.crossfadeStepProgress, 0)
        XCTAssertNil(player.activeCrossfade)

        player.isCrossfading = true
        player.crossfadeStepProgress = 0.4
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 5)

        player.stop()
        XCTAssertFalse(player.isCrossfading)
        XCTAssertEqual(player.crossfadeStepProgress, 0)
        XCTAssertNil(player.activeCrossfade)
    }

    func testCrossfadeSettingsRoundTripThroughServerConfig() throws {
        var config = ServerConfig.empty
        config.automixEnabled = true
        config.automixFadeDuration = 7
        config.automixApplyToAlbums = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

        XCTAssertTrue(decoded.effectiveAutomixEnabled)
        XCTAssertEqual(decoded.effectiveAutomixFadeDuration, 7)
        XCTAssertTrue(decoded.effectiveAutomixApplyToAlbums)
    }

    func testShouldCrossfadeRejectsShortIncomingTrack() {
        let player = Player()
        let first = mockSong("1", albumId: "a1", duration: 180)
        let shortNext = mockSong("2", albumId: "a2", duration: 6)
        player.queue = [first, shortNext]
        player.currentIndex = 0
        player.engineKind = .mpv
        player.configureCrossfade(enabled: true, fadeDuration: 5, applyToAlbums: true)

        XCTAssertFalse(player.shouldCrossfade(to: shortNext))
    }

    func testPreloadDoesNotAppendToMPVWhenCrossfadeEligible() {
        let player = Player()
        let first = mockSong("1", albumId: "a1")
        let nextDifferentAlbum = mockSong("2", albumId: "a2")
        player.queue = [first, nextDifferentAlbum]
        player.currentIndex = 0
        player.engineKind = .mpv
        player.configureCrossfade(enabled: true, fadeDuration: 5, applyToAlbums: false)
        player.onNextTrackPreloadRequest = { _ in URL(fileURLWithPath: "/tmp/next.opus") }

        player.preloadNextMPVTrack(nextDifferentAlbum)

        XCTAssertFalse(player.mpvEngine.hasAppendedTrack)
        XCTAssertNil(player.preloadedNextSongID)
    }

    func testCompleteCrossfadeResolvesDuplicateSongIndexCorrectly() {
        let player = Player()
        let song1 = mockSong("s1", albumId: "a1")
        let song2 = mockSong("s2", albumId: "a2")
        let song1Again = mockSong("s1", albumId: "a1")
        player.queue = [song1, song2, song1Again]
        player.currentIndex = 1
        player.crossfadeEngine = MPVPlaybackEngine()
        player.isCrossfading = true
        player.activeCrossfade = ActiveCrossfade(successorID: "s1", startTime: 100, duration: 5)

        player.completeCrossfade()

        XCTAssertEqual(player.currentIndex, 2)
    }

    func testPauseAndResumeShiftCrossfadeStartTimeInsteadOfAdvancing() {
        let player = Player()
        let first = mockSong("1")
        let second = mockSong("2")
        player.queue = [first, second]
        player.currentIndex = 0
        player.isPlaying = true
        player.crossfadeEngine = MPVPlaybackEngine()
        player.isCrossfading = true
        let initialStart = CFAbsoluteTimeGetCurrent() - 2.0
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: initialStart, duration: 5)

        player.pause()

        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.activeCrossfade?.pausedAt)

        player.activeCrossfade?.pausedAt = CFAbsoluteTimeGetCurrent() - 10.0
        player.resumeCrossfade()

        XCTAssertNil(player.activeCrossfade?.pausedAt)
        XCTAssertGreaterThan(player.activeCrossfade?.startTime ?? 0, initialStart + 9.0)
    }

    func testShuffleAndBeginScrubCancelCrossfade() {
        let player = Player()
        let first = mockSong("1")
        let second = mockSong("2")
        player.queue = [first, second]
        player.currentIndex = 0
        player.isCrossfading = true
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 5)

        player.toggleShuffle()
        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.activeCrossfade)

        player.isCrossfading = true
        player.activeCrossfade = ActiveCrossfade(successorID: "2", startTime: 100, duration: 5)

        player.beginScrub()
        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.activeCrossfade)
    }

    func testPlayMPVInitializesDurationFromAPIMetadata() {
        let player = Player()
        player.queue = [mockSong("s1", duration: 245)]
        player.currentIndex = 0

        player.playMPV(URL(string: "http://example.com/rest/stream?id=s1&format=opus")!)

        XCTAssertEqual(player.duration, 245, accuracy: 0.001)
        XCTAssertEqual(player.trackDuration, 245, accuracy: 0.001)
    }
}
