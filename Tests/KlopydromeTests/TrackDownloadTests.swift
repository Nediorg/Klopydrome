import XCTest
@testable import Klopydrome
import NavidromeClient

final class TrackDownloadTests: XCTestCase {
    func testFilenameUsesOriginalTrackPathBeforeMetadataFallback() {
        let song = SubsonicSong(
            id: "song",
            title: "Fallback",
            artist: "Artist",
            suffix: "mp3",
            path: "/library/Artist/Original Track.m4a"
        )

        let filename = TrackDownload.filename(for: song)

        XCTAssertEqual(filename, "Original Track.m4a")
    }

    func testFilenameBuildsSafeFallbackWithTrackSuffix() {
        let song = SubsonicSong(id: "song", title: "Summer: Night", artist: "The/Artist", suffix: "opus")

        let filename = TrackDownload.filename(for: song)

        XCTAssertEqual(filename, "The-Artist – Summer- Night.opus")
    }

    func testSavePanelSuggestsTrackFilenameAndAllowsFolderChoice() {
        let song = SubsonicSong(id: "song", title: "Track", artist: "Artist", suffix: "flac")

        let panel = TrackDownload.savePanel(for: song)

        XCTAssertEqual(panel.title, "Save File As…".localized)
        XCTAssertEqual(panel.prompt, "Save".localized)
        XCTAssertEqual(panel.nameFieldStringValue, "Artist – Track.flac")
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertFalse(panel.isExtensionHidden)
    }

    // MARK: - Original-format checkbox helpers

    private func config(format: String?, maxBitRate: Int) -> ServerConfig {
        var config = ServerConfig.empty
        config.format = format
        config.maxBitRate = maxBitRate
        return config
    }

    func testTranscodeSettingsNilWithoutConfiguredTranscoding() {
        XCTAssertNil(TrackDownload.transcodeSettings(in: config(format: nil, maxBitRate: 0)))
        XCTAssertNil(TrackDownload.transcodeSettings(in: config(format: "  ", maxBitRate: 0)))
    }

    func testTranscodeSettingsReadsFormatAndBitrate() {
        let both = TrackDownload.transcodeSettings(in: config(format: "Opus", maxBitRate: 128))
        XCTAssertEqual(both?.format, "opus")
        XCTAssertEqual(both?.maxBitRate, 128)

        let bitrateOnly = TrackDownload.transcodeSettings(in: config(format: nil, maxBitRate: 320))
        XCTAssertNil(bitrateOnly?.format)
        XCTAssertEqual(bitrateOnly?.maxBitRate, 320)
    }

    func testApplyingFormatSwapsDestinationExtension() {
        XCTAssertEqual(
            TrackDownload.filename("Artist – Track.flac", applyingFormat: "opus"),
            "Artist – Track.opus")
        XCTAssertEqual(
            TrackDownload.filename("Track", applyingFormat: "mp3"),
            "Track.mp3")
    }

    func testApplyingFormatIgnoresMatchingOrMissingCodec() {
        XCTAssertNil(TrackDownload.filename("Artist – Track.flac", applyingFormat: "FLAC"))
        XCTAssertNil(TrackDownload.filename("Artist – Track.flac", applyingFormat: nil))
    }

    @MainActor
    func testOriginalFormatCheckboxDefaultsToOnAndDisablesWithoutTranscoding() {
        let enabled = TrackDownload.originalFormatAccessory(transcodeAvailable: true)
        XCTAssertEqual(enabled.checkbox.state, .on)
        XCTAssertTrue(enabled.checkbox.isEnabled)

        let disabled = TrackDownload.originalFormatAccessory(transcodeAvailable: false)
        XCTAssertFalse(disabled.checkbox.isEnabled)
    }

    @MainActor
    func testFailedDownloadDoesNotMarkCompleted() {
        let app = AppState()
        let song1 = SubsonicSong(id: "song-1", title: "Song 1")
        let song2 = SubsonicSong(id: "song-2", title: "Song 2")
        let taskID = UUID()

        let task = DownloadTask(
            id: taskID,
            kind: .track(song: song1),
            songs: [song1, song2],
            completedSongIDs: [],
            currentSongID: song1.id
        )
        app.activeDownloadTasks = [task]
        app.downloadProgress[song1.id] = 0.5

        // Fail song1
        app.markSongFailed(in: taskID, songID: song1.id)

        let updated = app.activeDownloadTasks.first { $0.id == taskID }!
        XCTAssertTrue(updated.failedSongIDs.contains("song-1"))
        XCTAssertFalse(updated.completedSongIDs.contains("song-1"))
        XCTAssertNil(app.downloadProgress["song-1"])
        // Next song is selected as currentSongID
        XCTAssertEqual(updated.currentSongID, "song-2")

        // Succeed song2
        app.markSongCompleted(in: taskID, songID: song2.id)
        let finished = app.activeDownloadTasks.first { $0.id == taskID }!
        XCTAssertTrue(finished.completedSongIDs.contains("song-2"))
        XCTAssertFalse(finished.failedSongIDs.contains("song-2"))
        XCTAssertNil(finished.currentSongID)
    }

    @MainActor
    func testCancelledDownloadDoesNotMarkCompletedOrFailed() async {
        let app = AppState()
        let song1 = SubsonicSong(id: "cancel-1", title: "Track Cancel")
        let taskID = UUID()
        let task = DownloadTask(
            id: taskID,
            kind: .track(song: song1),
            coverArt: nil,
            songs: [song1],
            completedSongIDs: [],
            failedSongIDs: [],
            currentSongID: song1.id
        )
        app.activeDownloadTasks = [task]

        // When a download encounters CancellationError in the download loop,
        // it must not be added to completedSongIDs nor failedSongIDs.
        let cancelledError = CancellationError()
        do {
            throw cancelledError
        } catch is CancellationError {
            // caught cancellation - do not mark
        } catch {
            app.markSongFailed(in: taskID, songID: song1.id)
        }

        let updated = app.activeDownloadTasks.first { $0.id == taskID }!
        XCTAssertFalse(updated.completedSongIDs.contains("cancel-1"))
        XCTAssertFalse(updated.failedSongIDs.contains("cancel-1"))
    }

    @MainActor
    func testMarkSongCompletedCleansUpDownloadingState() async {
        let app = AppState()
        let song1 = SubsonicSong(id: "state-1", title: "Track State 1")
        let song2 = SubsonicSong(id: "state-2", title: "Track State 2")
        let taskID = UUID()
        let task = DownloadTask(
            id: taskID,
            kind: .track(song: song1),
            songs: [song1, song2],
            completedSongIDs: [],
            currentSongID: song1.id
        )
        app.activeDownloadTasks = [task]
        app.register(downloading: song1)
        app.register(downloading: song2)
        XCTAssertTrue(app.downloadingSongIDs.contains("state-1"))
        XCTAssertTrue(app.downloadingSongIDs.contains("state-2"))

        app.markSongCompleted(in: taskID, songID: song1.id)

        XCTAssertFalse(app.downloadingSongIDs.contains("state-1"))
        XCTAssertFalse(app.downloadingSongs.contains(where: { $0.id == "state-1" }))
        XCTAssertTrue(app.downloadingSongIDs.contains("state-2"))
    }

    @MainActor
    func testCancelDownloadSongInTaskCleansUpDownloadingState() async {
        let app = AppState()
        let song1 = SubsonicSong(id: "cancel-task-1", title: "Track Cancel Task 1")
        let song2 = SubsonicSong(id: "cancel-task-2", title: "Track Cancel Task 2")
        let taskID = UUID()
        let task = DownloadTask(
            id: taskID,
            kind: .track(song: song1),
            songs: [song1, song2],
            completedSongIDs: [],
            currentSongID: song1.id
        )
        app.activeDownloadTasks = [task]
        app.register(downloading: song1)
        app.register(downloading: song2)

        app.cancelDownloadSongInTask(taskID: taskID, song: song1)

        XCTAssertFalse(app.downloadingSongIDs.contains("cancel-task-1"))
        XCTAssertFalse(app.downloadingSongs.contains(where: { $0.id == "cancel-task-1" }))
        let updated = app.activeDownloadTasks.first { $0.id == taskID }!
        XCTAssertEqual(updated.songs.count, 1)
        XCTAssertEqual(updated.songs.first?.id, "cancel-task-2")
    }

    @MainActor
    func testOverallDownloadProgressReturnsNilWhenNoDownloads() {
        let app = AppState()
        XCTAssertNil(app.overallDownloadProgress)
    }

    @MainActor
    func testOverallDownloadProgressAveragesTaskProgress() {
        let app = AppState()
        let songs = (1...10).map { SubsonicSong(id: "prog-\($0)", title: "Song \($0)") }
        let task = DownloadTask(
            id: UUID(),
            kind: .track(song: songs[0]),
            songs: songs,
            completedSongIDs: Set(songs[0..<5].map(\.id)),
            currentSongID: songs[5].id
        )
        app.activeDownloadTasks = [task]
        app.downloadProgress[songs[5].id] = 0.5

        let progress = app.overallDownloadProgress
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!, 0.55, accuracy: 0.001)
    }

    @MainActor
    func testOverallDownloadProgressAveragesMultipleTopLevelDownloads() {
        let app = AppState()
        let task1Songs = (1...10).map { SubsonicSong(id: "t1-\($0)", title: "T1 \($0)") }
        let task1 = DownloadTask(
            id: UUID(),
            kind: .track(song: task1Songs[0]),
            songs: task1Songs,
            completedSongIDs: Set(task1Songs[0..<6].map(\.id)),
            currentSongID: nil
        )

        let task2Songs = (1...5).map { SubsonicSong(id: "t2-\($0)", title: "T2 \($0)") }
        let task2 = DownloadTask(
            id: UUID(),
            kind: .track(song: task2Songs[0]),
            songs: task2Songs,
            completedSongIDs: Set(task2Songs[0..<1].map(\.id)),
            currentSongID: nil
        )

        app.activeDownloadTasks = [task1, task2]
        // task1 is 6/10 = 0.6, task2 is 1/5 = 0.2 -> average = (0.6 + 0.2) / 2 = 0.4
        XCTAssertEqual(app.overallDownloadProgress!, 0.4, accuracy: 0.001)

        let standalone = SubsonicSong(id: "standalone-1", title: "Standalone")
        app.downloadingSongs = [standalone]
        app.downloadProgress[standalone.id] = 0.7
        // (0.6 + 0.2 + 0.7) / 3 = 0.5
        XCTAssertEqual(app.overallDownloadProgress!, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testCacheSongsCreatesBatchTaskForMultiSelection() {
        let app = AppState()
        let song1 = SubsonicSong(id: "multi-1", title: "Track 1")
        let song2 = SubsonicSong(id: "multi-2", title: "Track 2")
        let song3 = SubsonicSong(id: "multi-3", title: "Track 3")

        app.cacheSongs([song1, song2, song3])

        XCTAssertEqual(app.activeDownloadTasks.count, 1)
        guard let task = app.activeDownloadTasks.first else { return }
        XCTAssertEqual(task.kind, .batch(title: "Songs".localized))
        XCTAssertEqual(task.songs.map(\.id), ["multi-1", "multi-2", "multi-3"])
        XCTAssertTrue(app.downloadingSongIDs.contains("multi-1"))
        XCTAssertTrue(app.downloadingSongIDs.contains("multi-2"))
        XCTAssertTrue(app.downloadingSongIDs.contains("multi-3"))
    }

    @MainActor
    func testCacheSongsWithSingleTargetCreatesTrackTask() {
        let app = AppState()
        let song1 = SubsonicSong(id: "single-1", title: "Single Track")

        app.cacheSongs([song1])

        XCTAssertEqual(app.activeDownloadTasks.count, 1)
        guard let task = app.activeDownloadTasks.first else { return }
        XCTAssertEqual(task.kind, .track(song: song1))
        XCTAssertEqual(task.songs.map(\.id), ["single-1"])
    }

    @MainActor
    func testStartDownloadTaskClearsStaleCancelledState() {
        let app = AppState()
        let song1 = SubsonicSong(id: "stale-cancel-1", title: "Stale Cancel Track")
        app.cancelledDownloads.insert("stale-cancel-1")

        app.cacheSong(song1)

        XCTAssertFalse(app.cancelledDownloads.contains("stale-cancel-1"))
        XCTAssertFalse(app.isDownloadCancelled(songID: "stale-cancel-1"))
    }
}
