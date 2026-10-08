import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class DownloadAndOfflineCachingTests: XCTestCase {
    func testServerConfigDownloadAndOfflineDefaults() {
        let empty = ServerConfig.empty
        XCTAssertTrue(empty.effectiveDownloadTranscoded)
        XCTAssertFalse(empty.effectiveCacheStarredSongs)
        XCTAssertFalse(empty.effectiveCacheStarredAlbums)
        XCTAssertFalse(empty.effectiveCacheStarredArtists)

        var custom = ServerConfig.empty
        custom.downloadTranscoded = false
        custom.cacheStarredSongs = true
        custom.cacheStarredAlbums = true
        custom.cacheStarredArtists = true

        XCTAssertFalse(custom.effectiveDownloadTranscoded)
        XCTAssertTrue(custom.effectiveCacheStarredSongs)
        XCTAssertTrue(custom.effectiveCacheStarredAlbums)
        XCTAssertTrue(custom.effectiveCacheStarredArtists)
    }

    func testDownloadSuffixHonorsPreference() {
        let app = AppState()
        let song = SubsonicSong(id: "s1", title: "Song 1", suffix: "flac")

        // Default: downloadTranscoded = nil -> effective is true
        // format is nil -> effectiveSuffix is "flac"
        XCTAssertEqual(app.downloadSuffix(for: song), "flac")

        // Set transcode format to mp3
        app.serverConfig.format = "mp3"
        XCTAssertEqual(app.downloadSuffix(for: song), "mp3")

        // Turn off download transcoding -> downloads original flac
        app.serverConfig.downloadTranscoded = false
        XCTAssertEqual(app.downloadSuffix(for: song), "flac")
    }

    func testCandidateSuffixesIncludesBothTranscodeAndOriginal() {
        let app = AppState()
        app.serverConfig.format = "opus"
        app.serverConfig.downloadTranscoded = true

        let song = SubsonicSong(id: "s2", title: "Song 2", suffix: "flac")
        let candidates = app.candidateSuffixes(for: song)

        XCTAssertTrue(candidates.contains("opus"))
        XCTAssertTrue(candidates.contains("flac"))
        XCTAssertTrue(candidates.contains("mp3"))
    }

    func testPlaylistAndAlbumDownloadTrackingAndCancellation() {
        let app = AppState()
        let playlist = PlaylistSummary(id: "p1", name: "My Playlist", songCount: 2)
        let album = SubsonicAlbum(id: "a1", name: "My Album")
        let song1 = SubsonicSong(id: "s1", title: "Track 1")
        let song2 = SubsonicSong(id: "s2", title: "Track 2")

        XCTAssertFalse(app.isPlaylistDownloading("p1"))
        XCTAssertFalse(app.isAlbumDownloading("a1"))

        // Create playlist download task
        let playlistTask = DownloadTask(
            id: UUID(),
            kind: .playlist(playlist: playlist),
            coverArt: nil,
            songs: [song1, song2],
            completedSongIDs: [],
            currentSongID: "s1"
        )
        app.activeDownloadTasks.append(playlistTask)
        app.register(downloading: song1)
        app.register(downloading: song2)

        XCTAssertTrue(app.isPlaylistDownloading("p1"))
        XCTAssertTrue(app.downloadingSongIDs.contains("s1"))

        // Cancel playlist download
        app.cancelPlaylistDownload("p1")
        XCTAssertFalse(app.isPlaylistDownloading("p1"))
        XCTAssertFalse(app.downloadingSongIDs.contains("s1"))

        // Create album download task
        let albumTask = DownloadTask(
            id: UUID(),
            kind: .album(album: album),
            coverArt: nil,
            songs: [song1],
            completedSongIDs: [],
            currentSongID: "s1"
        )
        app.activeDownloadTasks.append(albumTask)
        app.register(downloading: song1)

        XCTAssertTrue(app.isAlbumDownloading("a1"))

        // Cancel single song download
        app.cancelSongDownload(song1)
        XCTAssertFalse(app.downloadingSongIDs.contains("s1"))
    }
}
