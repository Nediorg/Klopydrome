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

    func testClampDuration() {
        XCTAssertEqual(CrossfadeMath.clampDuration(0), 1)
        XCTAssertEqual(CrossfadeMath.clampDuration(20), 12)
        XCTAssertEqual(CrossfadeMath.clampDuration(6), 6)
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
}
