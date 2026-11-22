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

    func testCachedURLPurgesCorruptSmallFiles() throws {
        let app = AppState()
        let song = SubsonicSong(id: "corrupt_test_track", title: "Corrupt Track", suffix: "mp3")
        guard let cache = app.cache else { return }

        let key = CacheManager.streamKey(songId: song.id, suffix: "mp3")
        let fileURL = cache.fileURL(for: .streams, key: key)

        try Data().write(to: fileURL)
        app.cachedStreamKeys.insert(fileURL.lastPathComponent)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(app.cachedURL(for: song))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(app.cachedStreamKeys.contains(fileURL.lastPathComponent))
    }

    func testCachedURLPurgesTruncatedFilesForLongDurationTrack() throws {
        let app = AppState()
        let song = SubsonicSong(id: "truncated_track", title: "Truncated Track", suffix: "opus", duration: 180)
        guard let cache = app.cache else { return }

        let key = CacheManager.streamKey(songId: song.id, suffix: "opus")
        let fileURL = cache.fileURL(for: .streams, key: key)

        let truncatedData = Data(repeating: 0, count: 50_000)
        try truncatedData.write(to: fileURL)
        app.cachedStreamKeys.insert(fileURL.lastPathComponent)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(app.cachedURL(for: song))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(app.cachedStreamKeys.contains(fileURL.lastPathComponent))
    }

    func testMinimumExpectedCacheBytesFormula() {
        let shortSong = SubsonicSong(id: "s_short", duration: 0)
        XCTAssertEqual(AppState.minimumExpectedCacheBytes(for: shortSong), 4096)

        let longSong = SubsonicSong(id: "s_long", duration: 180)
        let expected = Int(Double(180) * 1500 * 0.75)
        XCTAssertEqual(AppState.minimumExpectedCacheBytes(for: longSong), expected)
    }

    func testScheduleBackgroundCacheIfNeededDoesNotRunWhenTrackIsCached() throws {
        let app = AppState()
        let song = SubsonicSong(id: "cached_song", title: "Cached Song", suffix: "mp3", duration: 10)
        guard let cache = app.cache else { return }

        let key = CacheManager.streamKey(songId: song.id, suffix: "mp3")
        let fileURL = cache.fileURL(for: .streams, key: key)
        let validData = Data(repeating: 0, count: 20_000)
        try validData.write(to: fileURL)
        app.cachedStreamKeys.insert(fileURL.lastPathComponent)

        XCTAssertNotNil(app.cachedURL(for: song))
        app.scheduleBackgroundCacheIfNeeded(for: song)

        XCTAssertFalse(app.player.isCaching)
        XCTAssertFalse(app.activeCacheTasks.contains(song.id))
    }
}
