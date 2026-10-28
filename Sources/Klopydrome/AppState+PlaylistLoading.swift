import Foundation
import NavidromeClient

extension AppState {
    /// Returns the current shared load snapshot for the requested playlist.
    func playlistLoadState(for playlist: PlaylistSummary) -> PlaylistLoadState? {
        playlistLoadStates[playlist.id]
    }

    /// Starts the one shared request used by the playlist detail view and its
    /// playback actions. Revalidates from the server on entry while showing cached
    /// data immediately without a layout jump or loading flicker.
    func loadPlaylistIfNeeded(_ playlist: PlaylistSummary, forceReload: Bool = false) {
        recordPlaylistAccess(playlist.id)
        let existing = playlistLoadStates[playlist.id]
        if forceReload {
            playlistLoadTasks[playlist.id]?.cancel()
            playlistLoadTasks[playlist.id] = nil
            playlistLoadTokens[playlist.id] = nil
        } else if let task = playlistLoadTasks[playlist.id], !task.isCancelled {
            return
        } else if let state = existing, state.matches(playlist) {
            return
        }

        let hasNoSongs = existing?.songs.isEmpty ?? true
        if hasNoSongs, !forceReload, let cached = cachedPlaylistDetail(for: playlist) {
            installCompletedPlaylist(cached, for: playlist)
            return
        }

        if isOfflineSession {
            loadOfflinePlaylistSession(for: playlist, existing: existing)
            return
        }

        guard let client else {
            if playlistLoadStates[playlist.id] == nil {
                playlistLoadStates[playlist.id] = PlaylistLoadState(summary: playlist, existing: existing)
            }
            return
        }

        let id = playlist.id
        let token = UUID()
        playlistLoadTokens[id] = token

        let hasLoadedSongs = !(playlistLoadStates[id]?.songs.isEmpty ?? true)
        var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist, existing: existing)
        if !hasLoadedSongs {
            state.isLoading = true
            state.error = nil
        }
        state.isSyncing = true
        playlistLoadStates[id] = state

        playlistLoadTasks[id] = Task { [weak self, client] in
            await self?.streamPlaylist(playlist, client: client, token: token, forceReload: forceReload)
        }
    }

    private func loadOfflinePlaylistSession(for playlist: PlaylistSummary, existing: PlaylistLoadState?) {
        Task {
            if let cached = await self.offlinePlaylistDetail(for: playlist.id) {
                await MainActor.run {
                    self.installCompletedPlaylist(cached, for: playlist)
                }
            } else if self.playlistLoadStates[playlist.id] == nil {
                await MainActor.run {
                    var state = PlaylistLoadState(summary: playlist, existing: existing)
                    state.isLoading = false
                    self.playlistLoadStates[playlist.id] = state
                }
            }
        }
    }

    /// Forces a fresh reload of a playlist (used by pull-to-refresh).
    func reloadPlaylist(_ playlist: PlaylistSummary) async {
        loadPlaylistIfNeeded(playlist, forceReload: true)
        if let task = playlistLoadTasks[playlist.id] {
            await task.value
        }
    }

    /// Awaits the same request used by the detail UI, then returns its complete
    /// song array for Player. If cached songs are already present in memory,
    /// returns them immediately so playback starts with zero delay.
    func playlistSongs(for playlist: PlaylistSummary) async -> [SubsonicSong] {
        loadPlaylistIfNeeded(playlist)
        if let state = playlistLoadState(for: playlist), !state.songs.isEmpty {
            return state.songs
        }
        if let task = playlistLoadTasks[playlist.id] {
            await task.value
        }
        return playlistLoadState(for: playlist)?.songs ?? []
    }

    /// Plays a playlist's tracks from the start, sharing the detail request
    /// with any open playlist screen instead of waiting for its rows to render.
    func play(_ playlist: PlaylistSummary) async {
        var songs = await playlistSongs(for: playlist)
        if isOfflineSession {
            songs = songs.filter { isCached($0) }
        }
        guard !songs.isEmpty else { return }
        play(songs, at: 0)
    }

    /// Shuffles a playlist's tracks through the shared detail request.
    func playShuffled(_ playlist: PlaylistSummary) async {
        var songs = await playlistSongs(for: playlist)
        if isOfflineSession {
            songs = songs.filter { isCached($0) }
        }
        guard !songs.isEmpty else { return }
        playShuffled(songs)
    }

    /// Queues a playlist's tracks to play immediately after the current song.
    func playNext(_ playlist: PlaylistSummary) async {
        var songs = await playlistSongs(for: playlist)
        if isOfflineSession {
            songs = songs.filter { isCached($0) }
        }
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        var queue = player.queue
        let insertAt = (player.currentIndex + 1) % queue.count
        queue.insert(contentsOf: songs, at: insertAt)
        player.queue = queue
    }

    /// Queues a playlist's tracks at the end of the queue ("В конец очереди").
    func playLater(_ playlist: PlaylistSummary) async {
        var songs = await playlistSongs(for: playlist)
        if isOfflineSession {
            songs = songs.filter { isCached($0) }
        }
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        player.queue.append(contentsOf: songs)
    }

    func cancelPlaylistLoads() {
        for task in playlistLoadTasks.values { task.cancel() }
        playlistLoadTasks = [:]
        playlistLoadTokens = [:]
        playlistLoadStates = [:]
    }

    func cancelPlaylistLoad(for playlistID: String) {
        playlistLoadTasks[playlistID]?.cancel()
        playlistLoadTasks[playlistID] = nil
        playlistLoadTokens[playlistID] = nil
        playlistLoadStates[playlistID] = nil
    }

    /// Cancels in-flight network streaming for the playlist without wiping its
    /// loaded in-memory state or songs.
    func cancelPlaylistTask(for playlistID: String) {
        playlistLoadTasks[playlistID]?.cancel()
        playlistLoadTasks[playlistID] = nil
        playlistLoadTokens[playlistID] = nil
        if var state = playlistLoadStates[playlistID] {
            state.isSyncing = false
            playlistLoadStates[playlistID] = state
        }
    }

    private func hydratePlaylistFromDiskCache(
        playlist: PlaylistSummary,
        id: String,
        token: UUID
    ) async -> Bool {
        guard let diskCached = await cachedPlaylistDetailFromDisk(for: id) else { return false }
        guard playlistLoadTokens[id] == token, !Task.isCancelled else { return false }

        if diskCached.changed == playlist.changed,
           diskCached.songCount == playlist.songCount {
            installCompletedPlaylist(diskCached, for: playlist)
            cachePlaylistDetail(diskCached)
            return true
        }

        var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
        if state.songs.isEmpty {
            state.detail = diskCached
            state.songs = diskCached.entry ?? []
            state.isLoading = false
            playlistLoadStates[id] = state
            cachePlaylistDetail(diskCached)
        }
        return false
    }

    private func streamPlaylist(
        _ playlist: PlaylistSummary,
        client: SubsonicClient,
        token: UUID,
        forceReload: Bool = false
    ) async {
        let id = playlist.id
        if !forceReload, await hydratePlaylistFromDiskCache(playlist: playlist, id: id, token: token) {
            playlistLoadTasks[id] = nil
            playlistLoadTokens[id] = nil
            return
        }

        do {
            try await streamPlaylistChunks(playlist, client: client, token: token)
        } catch {
            guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
            var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
            if state.songs.isEmpty, let offline = await offlinePlaylistDetail(for: id) {
                state.detail = offline
                state.songs = offline.entry ?? []
            }
            state.isLoading = false
            state.isSyncing = false
            if state.songs.isEmpty {
                state.error = error.localizedDescription
            }
            playlistLoadStates[id] = state
        }
        guard playlistLoadTokens[id] == token else { return }
        playlistLoadTasks[id] = nil
        playlistLoadTokens[id] = nil
    }

    private func streamPlaylistChunks(
        _ playlist: PlaylistSummary,
        client: SubsonicClient,
        token: UUID
    ) async throws {
        let id = playlist.id
        var didReplaceStaleSongs = false
        for try await chunk in client.getPlaylistChunked(id: id) {
            guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
            var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
            switch chunk {
            case .header(let detail):
                state.detail = detail
            case .songs(let songs):
                if !didReplaceStaleSongs {
                    state.songs = songs
                    didReplaceStaleSongs = true
                } else {
                    state.songs.append(contentsOf: songs)
                }
            }
            playlistLoadStates[id] = state
        }
        guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
        var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
        let songs = didReplaceStaleSongs ? state.songs : []
        let detail = playlistDetail(from: state.detail, playlist: playlist, songs: songs)
        let previousDetail = library.playlistDetails[id]
        let isUnchanged = previousDetail == detail

        state.detail = detail
        state.songs = songs
        state.isLoading = false
        state.isSyncing = false
        state.isComplete = true
        state.error = nil
        playlistLoadStates[id] = state
        recordPlaylistAccess(id)

        guard !isUnchanged else { return }

        cachePlaylistDetail(detail)
        await persistPlaylistDetailToDisk(detail)
        let repo = offlineRepository
        Task.detached(priority: .utility) {
            try? await repo?.savePlaylistDetail(detail)
        }
        syncPlaylistSummaryWithDetail(detail)
    }

    /// Keeps sidebar summaries and navigation history in sync with fresh detail metadata.
    func syncPlaylistSummaryWithDetail(_ detail: PlaylistDetail) {
        let id = detail.id
        let fresh = detail.summary
        if let idx = library.playlists.firstIndex(where: { $0.id == id }) {
            library.playlists[idx] = fresh
            if nav.selectedPlaylist?.id == id {
                nav.selectedPlaylist = fresh
            }
        }
        for (index, destination) in nav.history.enumerated() {
            if case .playlist(let summary) = destination, summary.id == id {
                nav.history[index] = .playlist(fresh)
            }
        }
    }

    private func installCompletedPlaylist(_ detail: PlaylistDetail, for playlist: PlaylistSummary) {
        recordPlaylistAccess(playlist.id)
        var state = PlaylistLoadState(summary: playlist)
        state.detail = detail
        state.songs = detail.entry ?? []
        state.isComplete = true
        state.isLoading = false
        state.isSyncing = false
        playlistLoadStates[playlist.id] = state
    }

    private func playlistDetail(
        from header: PlaylistDetail?,
        playlist: PlaylistSummary,
        songs: [SubsonicSong]
    ) -> PlaylistDetail {
        let source = header ?? PlaylistDetail(
            id: playlist.id,
            name: playlist.name,
            comment: playlist.comment,
            owner: playlist.owner,
            coverArt: playlist.coverArt,
            songCount: playlist.songCount,
            duration: playlist.duration,
            created: playlist.created,
            changed: playlist.changed,
            isPublic: playlist.isPublic,
            isReadonly: playlist.isReadonly,
            validUntil: playlist.validUntil
        )
        return PlaylistDetail(
            id: source.id,
            name: source.name,
            comment: source.comment,
            owner: source.owner,
            coverArt: source.coverArt,
            songCount: source.songCount,
            duration: source.duration,
            created: source.created,
            changed: source.changed,
            isPublic: source.isPublic,
            isReadonly: source.isReadonly,
            validUntil: source.validUntil,
            entry: songs
        )
    }

    /// Debug helper for Developer Mode: simulates a network error on the specified playlist
    func simulatePlaylistLoadError(for playlistID: String, message: String = "The request timed out.") {
        cancelPlaylistLoad(for: playlistID)
        if let summary = library.playlists.first(where: { $0.id == playlistID }) ?? nav.selectedPlaylist {
            var state = PlaylistLoadState(summary: summary)
            state.isLoading = false
            state.error = message
            state.songs = []
            playlistLoadStates[playlistID] = state
        }
    }
}
