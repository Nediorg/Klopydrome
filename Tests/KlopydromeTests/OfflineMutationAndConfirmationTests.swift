import XCTest
@testable import Klopydrome
import NavidromeClient

@MainActor
final class OfflineMutationAndConfirmationTests: XCTestCase {
    func testServerConfigSuppressionPreference() {
        let empty = ServerConfig.empty
        XCTAssertFalse(empty.effectiveSuppressOfflineActionWarning)

        var config = ServerConfig.empty
        config.suppressOfflineActionWarning = true
        XCTAssertTrue(config.effectiveSuppressOfflineActionWarning)

        config.suppressOfflineActionWarning = false
        XCTAssertFalse(config.effectiveSuppressOfflineActionWarning)
    }

    func testOfflineMutationStorePersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_mutations.json")
        let store = OfflineMutationStore(fileURL: fileURL)

        await store.recordStar(id: "song-1", kind: .song, isStarred: true)
        await store.recordStar(id: "album-1", kind: .album, isStarred: false)
        await store.recordRating(songID: "song-2", rating: 5)

        let initial = await store.currentMutations()
        XCTAssertEqual(initial.stars.count, 2)
        XCTAssertEqual(initial.stars["song-1"]?.isStarred, true)
        XCTAssertEqual(initial.stars["song-1"]?.kind, .song)
        XCTAssertEqual(initial.stars["album-1"]?.isStarred, false)
        XCTAssertEqual(initial.ratings["song-2"]?.rating, 5)

        // Reload fresh store from the same disk file
        let reloadedStore = OfflineMutationStore(fileURL: fileURL)
        let reloaded = await reloadedStore.currentMutations()
        XCTAssertEqual(reloaded.stars.count, 2)
        XCTAssertEqual(reloaded.ratings.count, 1)
        XCTAssertEqual(reloaded.ratings["song-2"]?.rating, 5)

        // Remove star and verify update persists
        await reloadedStore.removeStars(ids: ["song-1"])
        let afterRemove = await reloadedStore.currentMutations()
        XCTAssertNil(afterRemove.stars["song-1"])
        XCTAssertNotNil(afterRemove.stars["album-1"])

        // Clear all mutations
        await reloadedStore.clear()
        let cleared = await reloadedStore.currentMutations()
        XCTAssertTrue(cleared.stars.isEmpty)
        XCTAssertTrue(cleared.ratings.isEmpty)
    }

    func testConfirmOfflineActionWhenOnlineOrSuppressed() {
        let app = AppState()
        app.isOfflineSession = false
        app.serverConfig.effectiveSuppressOfflineActionWarning = false

        // When online, confirmOfflineAction always returns true without prompt
        XCTAssertTrue(app.confirmOfflineAction())

        // When offline but suppressed in preferences, returns true without prompt
        app.isOfflineSession = true
        app.serverConfig.effectiveSuppressOfflineActionWarning = true
        XCTAssertTrue(app.confirmOfflineAction())
    }

    func testOfflineStarAndRatingQueuedAndRestored() async {
        let app = AppState()
        app.isOfflineSession = true
        app.serverConfig.effectiveSuppressOfflineActionWarning = true
        app.serverConfig.effectiveSuppressOfflinePrompts = false
        app.serverConfig.url = "http://localhost:4533"

        let song = SubsonicSong(id: "test-track-1", title: "Test Track")
        XCTAssertFalse(app.isStarred(song))
        XCTAssertEqual(app.effectiveRating(for: song), 0)

        // Toggle star while offline
        app.toggleStar(song)
        XCTAssertTrue(app.isStarred(song))

        // Set rating while offline
        app.setRating(4, for: song)
        XCTAssertEqual(app.effectiveRating(for: song), 4)

        try? await Task.sleep(for: .milliseconds(50))

        // Check queued mutations
        if let store = app.ensureOfflineMutationStore() {
            let mutations = await store.currentMutations()
            XCTAssertEqual(mutations.stars["test-track-1"]?.isStarred, true)
            XCTAssertEqual(mutations.ratings["test-track-1"]?.rating, 4)

            // Clear in-memory overrides to simulate fresh app restart
            app.starOverrides.removeAll()
            app.ratingOverrides.removeAll()
            XCTAssertFalse(app.isStarred(song))
            XCTAssertEqual(app.effectiveRating(for: song), 0)

            // Restore from disk mutations
            await app.restorePendingOfflineMutations()
            XCTAssertTrue(app.isStarred(song))
            XCTAssertEqual(app.effectiveRating(for: song), 4)

            // Cleanup
            await store.clear()
        }
    }

    func testSidebarStatusCardStateResolution() {
        let app = AppState()
        XCTAssertNil(SidebarStatusCard.resolveStatus(for: app))

        app.isOfflineSession = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .offline(canReconnect: true)
        )

        app.serverConfig.forceOfflineMode = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .offline(canReconnect: false)
        )
        app.serverConfig.forceOfflineMode = false

        app.isReconnecting = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .connecting
        )

        app.isReconnecting = false
        app.isConnecting = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .connecting
        )
        app.isConnecting = false

        app.isServerScanning = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .scanningLibrary
        )

        app.isFlushingOfflineMutations = true
        XCTAssertEqual(
            SidebarStatusCard.resolveStatus(for: app),
            .applyingChanges
        )
    }

    func testServerConfigPendingMutationsAndScanSuppressionPreferences() {
        var config = ServerConfig.empty
        XCTAssertFalse(config.effectiveSuppressOfflinePrompts)
        XCTAssertFalse(config.effectiveSuppressServerScanWarning)

        config.effectiveSuppressOfflinePrompts = true
        config.suppressServerScanWarning = true
        XCTAssertTrue(config.effectiveSuppressOfflinePrompts)
        XCTAssertTrue(config.effectiveSuppressServerScanWarning)
    }

    func testOfflineMutationStorePlaylistActionsPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_playlist_mutations.json")
        let store = OfflineMutationStore(fileURL: fileURL)

        await store.recordPlaylistAdd(playlistID: "pl-1", songIDs: ["s-1", "s-2"])
        await store.recordPlaylistCreate(name: "Road Trip", songIDs: ["s-3"], comment: "Summer")

        let current = await store.currentMutations()
        XCTAssertFalse(current.isEmpty)
        XCTAssertEqual(current.playlists.count, 2)
        XCTAssertEqual(current.playlists[0].type, .addSongs)
        XCTAssertEqual(current.playlists[0].playlistID, "pl-1")
        XCTAssertEqual(current.playlists[1].type, .create)
        XCTAssertEqual(current.playlists[1].playlistName, "Road Trip")

        // Reload fresh from disk
        let reloaded = OfflineMutationStore(fileURL: fileURL)
        let reloadedMutations = await reloaded.currentMutations()
        XCTAssertEqual(reloadedMutations.playlists.count, 2)

        // Remove first action
        let firstID = current.playlists[0].id
        await reloaded.removePlaylists(ids: [firstID])
        let afterRemove = await reloaded.currentMutations()
        XCTAssertEqual(afterRemove.playlists.count, 1)
        XCTAssertEqual(afterRemove.playlists[0].playlistName, "Road Trip")
    }

    func testPendingActionsSummaryCategories() {
        let app = AppState()
        var mutations = OfflineMutations()
        XCTAssertTrue(app.pendingActionsSummary(for: mutations).isEmpty)

        mutations.playlists.append(
            QueuedPlaylistAction(
                id: "1",
                type: .addSongs,
                playlistID: "pl-1",
                playlistName: nil,
                songIDs: ["s-1"],
                comment: nil,
                timestamp: Date()
            )
        )
        let playlistSummary = app.pendingActionsSummary(for: mutations)
        XCTAssertEqual(playlistSummary, ["Изменение или добавление плейлистов".localized])

        mutations.stars["song-1"] = QueuedStarAction(id: "song-1", kind: .song, isStarred: true, timestamp: Date())
        let starAndPlaylist = app.pendingActionsSummary(for: mutations)
        XCTAssertEqual(starAndPlaylist.count, 2)
        XCTAssertTrue(starAndPlaylist.contains("Изменение или добавление плейлистов".localized))
        XCTAssertTrue(starAndPlaylist.contains("Отметки «Избранное»".localized))

        mutations.ratings["song-2"] = QueuedRatingAction(songID: "song-2", rating: 5, timestamp: Date())
        let allSummary = app.pendingActionsSummary(for: mutations)
        XCTAssertEqual(allSummary.count, 3)
        XCTAssertTrue(allSummary.contains("Оценки треков".localized))
    }

    func testPendingMutationsContextLocalization() {
        let prevSession = "С прошлого сеанса остались локальные изменения:".localized
        let offlineDisabled = "В офлайн-режиме накопились локальные изменения:".localized
        XCTAssertFalse(prevSession.isEmpty)
        XCTAssertFalse(offlineDisabled.isEmpty)
        XCTAssertNotEqual(prevSession, offlineDisabled)
    }

    func testSetWorkOfflineDisablingWithSuppressedPrompts() async {
        let app = AppState()
        app.serverConfig.forceOfflineMode = true
        app.serverConfig.effectiveSuppressOfflinePrompts = true

        await app.setWorkOffline(false)
        XCTAssertFalse(app.serverConfig.effectiveForceOfflineMode)
    }

    func testServerConfigSeparateOfflineActionAndSyncSuppression() {
        var config = ServerConfig.empty
        XCTAssertFalse(config.effectiveSuppressOfflinePrompts)
        XCTAssertFalse(config.effectiveSuppressOfflineActionWarning)

        config.effectiveSuppressOfflineActionWarning = true
        XCTAssertTrue(config.effectiveSuppressOfflineActionWarning)
        XCTAssertFalse(config.effectiveSuppressOfflinePrompts)

        config.effectiveSuppressOfflinePrompts = true
        XCTAssertTrue(config.effectiveSuppressOfflinePrompts)
        XCTAssertTrue(config.effectiveSuppressOfflineActionWarning)
    }

    func testOfflinePlaylistFollowQueuedAndRestored() async {
        let app = AppState()
        app.isOfflineSession = true
        app.serverConfig.effectiveSuppressOfflineActionWarning = true
        app.serverConfig.effectiveSuppressOfflinePrompts = false
        app.serverConfig.url = "http://localhost:4533"

        let testPlaylistID = "pl-test-\(UUID().uuidString)"
        app.followedPlaylistIDs.remove(testPlaylistID)
        let playlist = PlaylistSummary(id: testPlaylistID, name: "Favorites Playlist")
        XCTAssertFalse(app.isFollowed(playlist))

        // Follow playlist offline
        app.toggleFollow(playlist)
        XCTAssertTrue(app.isFollowed(playlist))

        try? await Task.sleep(for: .milliseconds(50))

        if let store = app.ensureOfflineMutationStore() {
            let mutations = await store.currentMutations()
            XCTAssertEqual(mutations.stars[testPlaylistID]?.isStarred, true)
            XCTAssertEqual(mutations.stars[testPlaylistID]?.kind, .playlist)

            // Simulate app restart / clear local state
            app.followedPlaylistIDs.removeAll()
            XCTAssertFalse(app.isFollowed(playlist))

            // Restore from disk mutations
            await app.restorePendingOfflineMutations()
            XCTAssertTrue(app.isFollowed(playlist))

            // Cleanup
            await store.clear()
            app.followedPlaylistIDs.remove(testPlaylistID)
        }
    }

    func testOfflinePlaylistCreateWithPublicFlagPersists() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_mutations.json")
        let store = OfflineMutationStore(fileURL: fileURL)

        await store.recordPlaylistCreate(
            name: "Public Playlist",
            songIDs: ["s1", "s2"],
            comment: "My comment",
            isPublic: true
        )

        let mutations = await store.currentMutations()
        XCTAssertEqual(mutations.playlists.count, 1)
        XCTAssertEqual(mutations.playlists.first?.playlistName, "Public Playlist")
        XCTAssertEqual(mutations.playlists.first?.isPublic, true)
        XCTAssertEqual(mutations.playlists.first?.comment, "My comment")

        let reloaded = OfflineMutationStore(fileURL: fileURL)
        let reloadedMutations = await reloaded.currentMutations()
        XCTAssertEqual(reloadedMutations.playlists.first?.isPublic, true)
    }

    func testOnlineStarFailureFallsBackToQueue() async {
        let app = AppState()
        app.serverConfig.url = "http://127.0.0.1:65534"
        let config = SubsonicConfig(
            baseURL: URL(string: "http://127.0.0.1:65534")!,
            username: "a",
            password: "b"
        )
        let client = SubsonicClient(config: config)
        app.client = client
        guard let store = app.ensureOfflineMutationStore() else {
            XCTFail("OfflineMutationStore could not be created")
            return
        }
        await store.clear()

        app.pushStarToServer(client: client, id: "fail-star-1", kind: .song, willStar: true)

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            let mutations = await store.currentMutations()
            if mutations.stars["fail-star-1"] != nil { break }
        }

        let mutations = await store.currentMutations()
        XCTAssertEqual(mutations.stars["fail-star-1"]?.isStarred, true)
        XCTAssertEqual(mutations.stars["fail-star-1"]?.kind, .song)
        await store.clear()
    }

    func testOnlineRatingFailureFallsBackToQueue() async {
        let app = AppState()
        app.serverConfig.url = "http://127.0.0.1:65534"
        let config = SubsonicConfig(
            baseURL: URL(string: "http://127.0.0.1:65534")!,
            username: "a",
            password: "b"
        )
        let client = SubsonicClient(config: config)
        app.client = client
        guard let store = app.ensureOfflineMutationStore() else {
            XCTFail("OfflineMutationStore could not be created")
            return
        }
        await store.clear()

        app.pushRatingToServer(client: client, id: "fail-rating-1", rating: 5)

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            let mutations = await store.currentMutations()
            if mutations.ratings["fail-rating-1"] != nil { break }
        }

        let mutations = await store.currentMutations()
        XCTAssertEqual(mutations.ratings["fail-rating-1"]?.rating, 5)
        await store.clear()
    }
}
