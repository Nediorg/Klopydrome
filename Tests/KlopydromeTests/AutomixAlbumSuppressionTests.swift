import XCTest
import NavidromeClient
@testable import Klopydrome

@MainActor
final class AutomixAlbumSuppressionTests: XCTestCase {

    private func mockSong(
        _ id: String,
        albumId: String? = nil,
        album: String? = nil,
        artist: String? = nil,
        track: Int? = nil,
        discNumber: Int? = nil,
        parent: String? = nil
    ) -> SubsonicSong {
        SubsonicSong(
            id: id,
            parent: parent,
            title: id,
            album: album,
            artist: artist,
            track: track,
            duration: 180,
            discNumber: discNumber,
            albumId: albumId
        )
    }

    // MARK: - Album Detection & Suppression

    func testApplyToAlbumsDefaultsToFalse() {
        let fresh = ServerConfig.empty
        XCTAssertFalse(fresh.effectiveAutomixApplyToAlbums)
    }

    func testSameAlbumMatchesMatchingAlbumId() {
        let song1 = mockSong("1", albumId: "alb-1")
        let song2 = mockSong("2", albumId: "alb-1")
        let song3 = mockSong("3", albumId: "alb-2")

        XCTAssertTrue(Player.isSameAlbum(song1, song2))
        XCTAssertFalse(Player.isSameAlbum(song1, song3))
    }

    func testSameAlbumFallsBackToParentIdWhenAlbumIdMissing() {
        let song1 = mockSong("1", parent: "dir-1")
        let song2 = mockSong("2", parent: "dir-1")
        let song3 = mockSong("3", parent: "dir-2")

        XCTAssertTrue(Player.isSameAlbum(song1, song2))
        XCTAssertFalse(Player.isSameAlbum(song1, song3))
    }

    func testSameAlbumMatchesAlbumTitleAndArtist() {
        let song1 = mockSong("1", album: "The Dark Side of the Moon", artist: "Pink Floyd")
        let song2 = mockSong("2", album: "the dark side of the moon", artist: "pink floyd")
        let song3 = mockSong("3", album: "The Dark Side of the Moon", artist: "Other Artist")

        XCTAssertTrue(Player.isSameAlbum(song1, song2))
        XCTAssertFalse(Player.isSameAlbum(song1, song3))
    }

    func testConsecutiveAlbumTrackDetectsInSequenceTracks() {
        let track1 = mockSong("1", track: 1, discNumber: 1)
        let track2 = mockSong("2", track: 2, discNumber: 1)
        let track4 = mockSong("4", track: 4, discNumber: 1)
        let disc2Track1 = mockSong("d2t1", track: 1, discNumber: 2)

        XCTAssertTrue(Player.isConsecutiveAlbumTrack(outgoing: track1, incoming: track2))
        XCTAssertFalse(Player.isConsecutiveAlbumTrack(outgoing: track1, incoming: track4))
        XCTAssertFalse(Player.isConsecutiveAlbumTrack(outgoing: track1, incoming: disc2Track1))
        XCTAssertFalse(Player.isConsecutiveAlbumTrack(outgoing: track2, incoming: disc2Track1))
    }

    func testIntraAlbumTransitionSuppressesCrossfadeWithinAlbumEvenWhenShuffled() {
        let track1 = mockSong("1", albumId: "alb-1", track: 1)
        let track2 = mockSong("2", albumId: "alb-1", track: 2)
        let track5 = mockSong("5", albumId: "alb-1", track: 5)
        let diffAlb = mockSong("diff", albumId: "alb-2", track: 6)

        // Intra-album transitions are detected regardless of sequential order or shuffle state
        XCTAssertTrue(Player.isIntraAlbumTransition(outgoing: track1, incoming: track2, isShuffled: false))
        XCTAssertTrue(Player.isIntraAlbumTransition(outgoing: track1, incoming: track5, isShuffled: false))
        XCTAssertTrue(Player.isIntraAlbumTransition(outgoing: track1, incoming: track2, isShuffled: true))
        XCTAssertTrue(Player.isIntraAlbumTransition(outgoing: track1, incoming: track5, isShuffled: true))
        XCTAssertFalse(Player.isIntraAlbumTransition(outgoing: track1, incoming: diffAlb, isShuffled: false))
        XCTAssertFalse(Player.isIntraAlbumTransition(outgoing: track1, incoming: diffAlb, isShuffled: true))
    }

    func testSameAlbumMatchesAcrossAlbumIdAndParentId() {
        let song1 = mockSong("1", albumId: "alb-1")
        let song2 = mockSong("2", parent: "alb-1")

        XCTAssertTrue(Player.isSameAlbum(song1, song2))
    }

    func testSameAlbumMatchesWithFeaturingArtists() {
        let song1 = mockSong("1", album: "Starboy", artist: "The Weeknd")
        let song2 = mockSong("2", album: "Starboy", artist: "The Weeknd feat. Daft Punk")

        XCTAssertTrue(Player.isSameAlbum(song1, song2))
    }

    func testEvaluateCrossfadeSuppressedForIntraAlbumTracksByDefault() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("1", albumId: "alb-1", track: 1)
        let song2 = mockSong("2", albumId: "alb-1", track: 2)
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.currentTime = 178
        player.isPlaying = true
        player.automix.enabled = true
        player.automix.applyToAlbums = false
        player.automix.preloadedNextSong = song2
        player.automix.preloadedNextSongID = song2.id
        player.preparePreloadedMPVEngine().setIsLoadedForTesting(true)

        player.evaluateAutomixCrossfade(at: 178)

        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.automix.activeCrossfade)
    }

    func testEvaluateCrossfadeAllowedForIntraAlbumTracksWhenApplyToAlbumsIsTrue() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("1", albumId: "alb-1", track: 1)
        let song2 = mockSong("2", albumId: "alb-1", track: 2)
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.currentTime = 178
        player.isPlaying = true
        player.automix.enabled = true
        player.automix.applyToAlbums = true
        player.automix.preloadedNextSong = song2
        player.automix.preloadedNextSongID = song2.id
        player.preparePreloadedMPVEngine().setIsLoadedForTesting(true)

        player.evaluateAutomixCrossfade(at: 178)

        XCTAssertTrue(player.isCrossfading)
        XCTAssertNotNil(player.automix.activeCrossfade)
    }

    func testEvaluateCrossfadeAllowedForDifferentAlbumsEvenWhenApplyToAlbumsIsFalse() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("1", albumId: "alb-1", track: 1)
        let song2 = mockSong("2", albumId: "alb-2", track: 2)
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.currentTime = 178
        player.isPlaying = true
        player.automix.enabled = true
        player.automix.applyToAlbums = false
        player.automix.preloadedNextSong = song2
        player.automix.preloadedNextSongID = song2.id
        player.preparePreloadedMPVEngine().setIsLoadedForTesting(true)

        player.evaluateAutomixCrossfade(at: 178)

        XCTAssertTrue(player.isCrossfading)
        XCTAssertNotNil(player.automix.activeCrossfade)
    }

    func testEvaluateCrossfadeAbortsActiveCrossfadeIfIntraAlbumTransitionDetected() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song1 = mockSong("1", albumId: "alb-1", track: 1)
        let song2 = mockSong("2", albumId: "alb-1", track: 2)
        player.queue = [song1, song2]
        player.currentIndex = 0
        player.currentTime = 178
        player.isPlaying = true
        player.automix.enabled = true
        player.automix.applyToAlbums = false
        player.automix.preloadedNextSong = song2
        player.automix.preloadedNextSongID = song2.id
        player.preparePreloadedMPVEngine().setIsLoadedForTesting(true)
        player.automix.activeCrossfade = ActiveAutomixCrossfade(
            successorID: song2.id,
            startTime: 175,
            duration: 5
        )
        player.isCrossfading = true

        player.evaluateAutomixCrossfade(at: 178)

        XCTAssertFalse(player.isCrossfading)
        XCTAssertNil(player.automix.activeCrossfade)
    }
}
