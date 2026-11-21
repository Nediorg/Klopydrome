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

    func testEffectiveSuffixUsesMP3ForBitRateOnlyTranscode() {
        let app = AppState()
        app.serverConfig.format = nil
        app.serverConfig.maxBitRate = 192
        let song = SubsonicSong(id: "s_flac", title: "FLAC Track", suffix: "flac")

        XCTAssertEqual(app.effectiveSuffix(for: song), "mp3")
    }

    func testBeginAutomaticPlaybackCacheSkipsTimeOffsetTranscodeRestart() throws {
        let app = AppState()
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        app.cache = CacheManager(rootURL: tempRoot)
        app.serverConfig.cacheEnabled = true
        app.serverConfig.playbackEngine = .mpv
        let song = SubsonicSong(id: "s_seek", title: "Seek Track", suffix: "opus", duration: 180)
        let seekURL = try XCTUnwrap(URL(string: "http://host/rest/stream?id=s_seek&format=opus&timeOffset=45"))

        XCTAssertNil(app.beginAutomaticPlaybackCache(for: song, streamURL: seekURL))
        XCTAssertNil(app.automaticPlaybackRecording)
    }

    func testFinishAutomaticPlaybackCacheRejectsPrematureEOFAndMovesCompleteStream() async throws {
        let app = AppState()
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let cache = CacheManager(rootURL: tempRoot)
        app.cache = cache
        app.serverConfig.cacheEnabled = true
        app.serverConfig.playbackEngine = .mpv

        let song = SubsonicSong(id: "s_eof", title: "Opus Track", suffix: "opus", duration: 180)
        let streamURL = try XCTUnwrap(URL(string: "http://host/rest/stream?id=s_eof"))

        // Premature EOF after 25s despite enough bytes for legacy bitrate threshold -> rejected
        let recURL1 = try XCTUnwrap(app.beginAutomaticPlaybackCache(for: song, streamURL: streamURL))
        var payload = Data([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        payload.append(Data(repeating: 1, count: 250_000))
        try payload.write(to: recURL1)

        await app.finishAutomaticPlaybackCache(MPVPlaybackEngine.StreamRecordCompletion(
            url: recURL1,
            reachedTime: 25,
            streamDuration: 180
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recURL1.path))
        XCTAssertNil(app.cachedURL(for: song))

        // Completed transcoded stream (streamDuration == 0 -> uses song.duration == 180 from API) -> cached
        let recURL2 = try XCTUnwrap(app.beginAutomaticPlaybackCache(for: song, streamURL: streamURL))
        try payload.write(to: recURL2)

        await app.finishAutomaticPlaybackCache(MPVPlaybackEngine.StreamRecordCompletion(
            url: recURL2,
            reachedTime: 178,
            streamDuration: 0
        ))
        XCTAssertNotNil(app.cachedURL(for: song))
    }

    func testFinishAutomaticPlaybackCacheHonorsSilenceTrimMargin() async throws {
        let app = AppState()
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        app.cache = CacheManager(rootURL: tempRoot)
        app.serverConfig.cacheEnabled = true
        app.serverConfig.playbackEngine = .mpv
        app.player.silenceTrimMode = .strong

        let song = SubsonicSong(id: "s_trim", title: "Trimmed Track", suffix: "opus", duration: 180)
        let streamURL = try XCTUnwrap(URL(string: "http://host/rest/stream?id=s_trim"))
        let recURL = try XCTUnwrap(app.beginAutomaticPlaybackCache(for: song, streamURL: streamURL))
        var payload = Data([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        payload.append(Data(repeating: 1, count: 250_000))
        try payload.write(to: recURL)

        await app.finishAutomaticPlaybackCache(MPVPlaybackEngine.StreamRecordCompletion(
            url: recURL,
            reachedTime: 162,
            streamDuration: 180
        ))
        XCTAssertNotNil(app.cachedURL(for: song))

        // Premature EOF where mpv reported rolling buffer duration == reachedTime (25s) on a 180s song -> rejected
        let brokenSong = SubsonicSong(id: "s_rolling", title: "Rolling Track", suffix: "opus", duration: 180)
        let brokenStreamURL = try XCTUnwrap(URL(string: "http://host/rest/stream?id=s_rolling"))
        let brokenRecURL = try XCTUnwrap(app.beginAutomaticPlaybackCache(for: brokenSong, streamURL: brokenStreamURL))
        try payload.write(to: brokenRecURL)

        await app.finishAutomaticPlaybackCache(MPVPlaybackEngine.StreamRecordCompletion(
            url: brokenRecURL,
            reachedTime: 25,
            streamDuration: 25
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenRecURL.path))
        XCTAssertNil(app.cachedURL(for: brokenSong))
    }

    func testPrematureLocalCacheEOFOnSeekTriggersRecoveryInsteadOfNextTrack() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song = SubsonicSong(id: "s_corrupt", title: "Corrupt Track", suffix: "opus", duration: 262)
        player.queue = [song, SubsonicSong(id: "s_next", title: "Next", duration: 180)]
        player.currentIndex = 0
        player.currentSourceURL = URL(fileURLWithPath: "/tmp/s_corrupt.opus")
        player.mpvEngine.setIsLoadedForTesting(true)

        var endedCount = 0
        var recoveredID: String?
        player.onTrackEnded = { endedCount += 1 }
        player.onLocalFilePlaybackFailed = { recoveredID = $0.id }

        player.seek(to: 60.0)
        player.mpvEngine.onTrackEnded?()

        XCTAssertEqual(endedCount, 0)
        XCTAssertEqual(recoveredID, "s_corrupt")
        XCTAssertEqual(player.pendingSeekTime ?? 0, 60.0, accuracy: 0.001)
        XCTAssertNil(player.currentSourceURL)
    }

    func testGrosslyTruncatedLocalCacheEOFWithoutSeekTriggersRecovery() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        let song = SubsonicSong(id: "s_trunc", title: "Truncated", suffix: "opus", duration: 262)
        player.queue = [song]
        player.currentIndex = 0
        player.currentSourceURL = URL(fileURLWithPath: "/tmp/s_trunc.opus")
        player.currentTime = 10.0

        var endedCount = 0
        var recoveredID: String?
        player.onTrackEnded = { endedCount += 1 }
        player.onLocalFilePlaybackFailed = { recoveredID = $0.id }

        player.mpvEngine.onTrackEnded?()

        XCTAssertEqual(endedCount, 0)
        XCTAssertEqual(recoveredID, "s_trunc")
    }

    func testNormalLocalCacheEOFWithSilenceTrimAdvancesNormally() {
        let player = Player()
        player.setEngineKindForTesting(.mpv)
        player.silenceTrimMode = .strong
        let song = SubsonicSong(id: "s_ok", title: "Valid", suffix: "opus", duration: 200)
        player.queue = [song]
        player.currentIndex = 0
        player.currentSourceURL = URL(fileURLWithPath: "/tmp/s_ok.opus")
        player.currentTime = 185.0

        var endedCount = 0
        var failedCount = 0
        player.onTrackEnded = { endedCount += 1 }
        player.onLocalFilePlaybackFailed = { _ in failedCount += 1 }

        player.mpvEngine.onTrackEnded?()

        XCTAssertEqual(endedCount, 1)
        XCTAssertEqual(failedCount, 0)
    }

    func testDownloadQueueSequentialStateTransition() {
        let app = AppState()
        let song1 = SubsonicSong(id: "q1", title: "Track 1")
        let song2 = SubsonicSong(id: "q2", title: "Track 2")

        app.startDownloadTask(kind: .track(song: song1), coverArt: nil, songs: [song1])
        app.startDownloadTask(kind: .track(song: song2), coverArt: nil, songs: [song2])

        XCTAssertEqual(app.activeDownloadTasks.count, 2)
        XCTAssertEqual(app.activeDownloadTasks[0].state, .active)
        XCTAssertEqual(app.activeDownloadTasks[1].state, .queued)
    }

    func testDownloadTaskCancellationAdvancesQueue() {
        let app = AppState()
        let song1 = SubsonicSong(id: "c1", title: "Track 1")
        let song2 = SubsonicSong(id: "c2", title: "Track 2")

        app.startDownloadTask(kind: .track(song: song1), coverArt: nil, songs: [song1])
        app.startDownloadTask(kind: .track(song: song2), coverArt: nil, songs: [song2])

        let first = app.activeDownloadTasks[0]
        app.cancelDownloadTask(first)

        XCTAssertEqual(app.activeDownloadTasks.count, 1)
        XCTAssertEqual(app.activeDownloadTasks[0].songs.first?.id, "c2")
        XCTAssertEqual(app.activeDownloadTasks[0].state, .active)
    }

    func testWaitingForNetworkStateShowsOfflineSubtitle() {
        let song = SubsonicSong(id: "net1", title: "Network Test")
        var task = DownloadTask(
            id: UUID(),
            kind: .track(song: song),
            coverArt: nil,
            songs: [song],
            completedSongIDs: [],
            currentSongID: "net1",
            state: .waitingForNetwork
        )

        XCTAssertEqual(task.currentSongSubtitle, "Offline".localized)

        task.state = .active
        XCTAssertEqual(task.currentSongSubtitle, "Network Test")
    }
}
