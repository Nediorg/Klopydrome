import Foundation
import NavidromeClient

extension AppState {
    /// Returns the current shared load snapshot only while it still matches the
    /// manifest item that opened the detail page.
    func playlistLoadState(for playlist: PlaylistSummary) -> PlaylistLoadState? {
        guard let state = playlistLoadStates[playlist.id], state.matches(playlist) else {
            return nil
        }
        return state
    }

    /// Starts the one shared request used by the playlist detail view and its
    /// playback actions. Repeated callers join the existing request instead of
    /// opening another `getPlaylist` connection.
    func loadPlaylistIfNeeded(_ playlist: PlaylistSummary, forceReload: Bool = false) {
        if forceReload {
            cancelPlaylistLoad(for: playlist.id)
        }
        if let state = playlistLoadState(for: playlist), state.isLoading || state.isComplete {
            return
        }
        if !forceReload, let cached = cachedPlaylistDetail(for: playlist) {
            installCompletedPlaylist(cached, for: playlist)
            return
        }
        if isOfflineSession, let cached = offlinePlaylistDetail(for: playlist.id) {
            installCompletedPlaylist(cached, for: playlist)
            return
        }
        guard let client else {
            playlistLoadStates[playlist.id] = PlaylistLoadState(summary: playlist)
            return
        }

        let id = playlist.id
        let token = UUID()
        playlistLoadTokens[id] = token
        var state = PlaylistLoadState(summary: playlist)
        state.isLoading = true
        playlistLoadStates[id] = state
        playlistLoadTasks[id] = Task { [weak self, client] in
            await self?.streamPlaylist(playlist, client: client, token: token)
        }
    }

    /// Awaits the same request used by the detail UI, then returns its complete
    /// song array for Player. No SwiftUI row needs to be materialized first.
    func playlistSongs(for playlist: PlaylistSummary) async -> [SubsonicSong] {
        loadPlaylistIfNeeded(playlist)
        if let task = playlistLoadTasks[playlist.id] {
            await task.value
        }
        return playlistLoadState(for: playlist)?.songs ?? []
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

    private func streamPlaylist(
        _ playlist: PlaylistSummary,
        client: SubsonicClient,
        token: UUID
    ) async {
        let id = playlist.id
        do {
            for try await chunk in client.getPlaylistChunked(id: id) {
                guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
                var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
                switch chunk {
                case .header(let detail):
                    state.detail = detail
                case .songs(let songs):
                    state.songs.append(contentsOf: songs)
                }
                playlistLoadStates[id] = state
            }
            guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
            var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
            let detail = playlistDetail(from: state.detail, playlist: playlist, songs: state.songs)
            state.detail = detail
            state.isLoading = false
            state.isComplete = true
            playlistLoadStates[id] = state
            cachePlaylistDetail(detail)
            await persistOfflinePlaylistDetail(detail)
        } catch {
            guard playlistLoadTokens[id] == token, !Task.isCancelled else { return }
            var state = playlistLoadStates[id] ?? PlaylistLoadState(summary: playlist)
            state.isLoading = false
            state.error = error.localizedDescription
            playlistLoadStates[id] = state
        }
        guard playlistLoadTokens[id] == token else { return }
        playlistLoadTasks[id] = nil
        playlistLoadTokens[id] = nil
    }

    private func installCompletedPlaylist(_ detail: PlaylistDetail, for playlist: PlaylistSummary) {
        var state = PlaylistLoadState(summary: playlist)
        state.detail = detail
        state.songs = detail.entry ?? []
        state.isComplete = true
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
}
