import Foundation
import NavidromeClient

extension AppState {
    func addToPlaylist(_ songs: [SubsonicSong], playlistID: String) async {
        guard confirmOfflineAction() else { return }
        if let client {
            try? await client.updatePlaylist(id: playlistID, addSongIds: songs.map(\.id))
            recordRecentPlaylist(playlistID)
            invalidatePlaylistDetail(for: playlistID)
            await refreshPlaylists()
            let isCurrent = nav.selectedPlaylist?.id == playlistID || nav.history.last?.playlistID == playlistID
            if let updated = library.playlists.first(where: { $0.id == playlistID }), isCurrent {
                await reloadPlaylist(updated)
            }
        } else {
            queueOfflineAddToPlaylist(playlistID: playlistID, songIDs: songs.map(\.id))
            recordRecentPlaylist(playlistID)
        }
    }

    @discardableResult
    func createPlaylist(
        name: String,
        songs: [SubsonicSong],
        comment: String? = nil,
        isPublic: Bool = false
    ) async -> PlaylistDetail? {
        guard confirmOfflineAction() else { return nil }
        if let client {
            let created = try? await client.createPlaylist(name: name, songIds: songs.map(\.id))
            guard let id = created?.id else { return nil }
            recordRecentPlaylist(id)
            if (comment != nil && !comment!.isEmpty) || isPublic {
                try? await client.updatePlaylist(id: id, comment: comment, isPublic: isPublic)
            }
            await refreshPlaylists()
            return created
        } else {
            queueOfflineCreatePlaylist(name: name, songIDs: songs.map(\.id), comment: comment, isPublic: isPublic)
            let tempID = "offline_\(UUID().uuidString)"
            let localSummary = PlaylistSummary(
                id: tempID,
                name: name,
                comment: comment,
                songCount: songs.count,
                duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
                isPublic: isPublic
            )
            library.playlists.insert(localSummary, at: 0)
            recordRecentPlaylist(tempID)
            if let offlineRepository {
                let detail = PlaylistDetail(
                    id: tempID,
                    name: name,
                    comment: comment,
                    songCount: songs.count,
                    duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
                    isPublic: isPublic,
                    entry: songs
                )
                try? await offlineRepository.savePlaylistDetail(detail)
            }
            return nil
        }
    }

    func recordRecentPlaylist(_ id: String) {
        var recent = recentPlaylistIDs
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recentPlaylistIDs = Array(recent.prefix(10))
    }

    func refreshPlaylists() async {
        guard let client else { return }
        guard let fresh = try? await client.getPlaylists() else { return }
        let summariesByID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        library.playlistDetails = library.playlistDetails.filter { id, detail in
            guard let summary = summariesByID[id] else { return false }
            return detail.changed == summary.changed && detail.songCount == summary.songCount
        }
        library.playlists = fresh
        library.playlistsLoaded = true
        await persistOfflinePlaylists(fresh)
        await persistPlaylistsToDisk()
    }

    func cachedPlaylistDetail(for playlist: PlaylistSummary) -> PlaylistDetail? {
        guard let detail = library.playlistDetails[playlist.id],
              detail.changed == playlist.changed,
              detail.songCount == playlist.songCount else {
            return nil
        }
        return detail
    }

    func cachePlaylistDetail(_ detail: PlaylistDetail) {
        library.playlistDetails[detail.id] = detail
        library.recordPlaylistDetailAccess(detail.id)
    }

    func invalidatePlaylistDetail(for playlistID: String) {
        cancelPlaylistLoad(for: playlistID)
        library.playlistDetails[playlistID] = nil
        if player.currentPlaylist?.id == playlistID {
            player.playbackContext = nil
        }
        Task { [weak self] in
            await self?.cache?.removeFile(for: .metadata, key: "detail_playlist_\(playlistID)")
        }
    }

    func removeSongsFromPlaylist(playlistID: String, at indices: [Int]) async {
        guard confirmOfflineAction() else { return }
        guard !indices.isEmpty else { return }
        guard let removedPairs = await applyOptimisticPlaylistRemoval(
            playlistID: playlistID,
            indices: indices
        ) else { return }

        guard let client else { return }

        do {
            try await client.updatePlaylist(id: playlistID, removeIndexes: indices)
            await refreshPlaylists()
            if let serverSummary = library.playlists.first(where: { $0.id == playlistID }) {
                await applyServerPlaylistRemoval(playlistID: playlistID, serverSummary: serverSummary)
            }
        } catch {
            rollbackPlaylistRemoval(playlistID: playlistID, removedPairs: removedPairs, error: error)
        }
    }

    private func applyOptimisticPlaylistRemoval(
        playlistID: String,
        indices: [Int]
    ) async -> [(index: Int, song: SubsonicSong)]? {
        guard var state = playlistLoadStates[playlistID] else { return nil }

        let sortedIndices = indices.sorted(by: >).filter { state.songs.indices.contains($0) }
        guard !sortedIndices.isEmpty else { return nil }

        var removedPairs: [(index: Int, song: SubsonicSong)] = []
        var totalDurationRemoved = 0

        for idx in sortedIndices {
            let removed = state.songs.remove(at: idx)
            removedPairs.append((index: idx, song: removed))
            totalDurationRemoved += (removed.duration ?? 0)
        }

        let newCount = state.songs.count
        state.songCount = newCount
        let newDuration = max(0, (state.detail?.duration ?? 0) - totalDurationRemoved)

        if let oldDetail = state.detail {
            let updatedDetail = PlaylistDetail(
                id: oldDetail.id,
                name: oldDetail.name,
                comment: oldDetail.comment,
                owner: oldDetail.owner,
                coverArt: oldDetail.coverArt,
                songCount: newCount,
                duration: newDuration,
                created: oldDetail.created,
                changed: oldDetail.changed,
                isPublic: oldDetail.isPublic,
                isReadonly: oldDetail.isReadonly,
                validUntil: oldDetail.validUntil,
                entry: state.songs
            )
            state.detail = updatedDetail
            cachePlaylistDetail(updatedDetail)
            await persistPlaylistDetailToDisk(updatedDetail)
            let repo = offlineRepository
            Task.detached(priority: .utility) {
                try? await repo?.savePlaylistDetail(updatedDetail)
            }
            syncPlaylistSummaryWithDetail(updatedDetail)
        }

        playlistLoadStates[playlistID] = state

        if player.currentPlaylist?.id == playlistID {
            let removedIDs = Set(removedPairs.map(\.song.id))
            for (qIdx, qSong) in player.queue.enumerated().reversed() where removedIDs.contains(qSong.id) {
                player.remove(at: qIdx)
            }
        }

        return removedPairs
    }

    private func applyServerPlaylistRemoval(playlistID: String, serverSummary: PlaylistSummary) async {
        guard var current = playlistLoadStates[playlistID] else { return }
        current.changed = serverSummary.changed
        if let oldDetail = current.detail {
            let syncedDetail = PlaylistDetail(
                id: oldDetail.id,
                name: oldDetail.name,
                comment: oldDetail.comment,
                owner: oldDetail.owner,
                coverArt: oldDetail.coverArt,
                songCount: serverSummary.songCount ?? oldDetail.songCount,
                duration: serverSummary.duration ?? oldDetail.duration,
                created: oldDetail.created,
                changed: serverSummary.changed,
                isPublic: oldDetail.isPublic,
                isReadonly: oldDetail.isReadonly,
                validUntil: oldDetail.validUntil,
                entry: current.songs
            )
            current.detail = syncedDetail
            cachePlaylistDetail(syncedDetail)
            await persistPlaylistDetailToDisk(syncedDetail)
        }
        playlistLoadStates[playlistID] = current
    }

    private func rollbackPlaylistRemoval(
        playlistID: String,
        removedPairs: [(index: Int, song: SubsonicSong)],
        error: Error
    ) {
        guard var rollbackState = playlistLoadStates[playlistID] else { return }
        for pair in removedPairs.reversed() {
            let insertIdx = min(pair.index, rollbackState.songs.count)
            rollbackState.songs.insert(pair.song, at: insertIdx)
        }
        rollbackState.songCount = rollbackState.songs.count
        if let oldDetail = rollbackState.detail {
            let totalDurationRemoved = removedPairs.reduce(0) { $0 + ($1.song.duration ?? 0) }
            let rolledBackDetail = PlaylistDetail(
                id: oldDetail.id,
                name: oldDetail.name,
                comment: oldDetail.comment,
                owner: oldDetail.owner,
                coverArt: oldDetail.coverArt,
                songCount: rollbackState.songs.count,
                duration: (oldDetail.duration ?? 0) + totalDurationRemoved,
                created: oldDetail.created,
                changed: oldDetail.changed,
                isPublic: oldDetail.isPublic,
                isReadonly: oldDetail.isReadonly,
                validUntil: oldDetail.validUntil,
                entry: rollbackState.songs
            )
            rollbackState.detail = rolledBackDetail
            cachePlaylistDetail(rolledBackDetail)
            syncPlaylistSummaryWithDetail(rolledBackDetail)
        }
        rollbackState.error = error.localizedDescription
        playlistLoadStates[playlistID] = rollbackState
    }

    func removeSongFromPlaylist(playlistID: String, at index: Int) async {
        await removeSongsFromPlaylist(playlistID: playlistID, at: [index])
    }

    func removeSong(
        _ song: SubsonicSong,
        from playlist: PlaylistSummary,
        at specificIndex: Int? = nil
    ) async {
        let playlistID = playlist.id
        var state = playlistLoadStates[playlistID]
        if state == nil || state?.songs.isEmpty == true {
            _ = await playlistSongs(for: playlist)
            state = playlistLoadStates[playlistID]
        }
        guard let songs = state?.songs, !songs.isEmpty else { return }

        let targetIndex: Int
        if let specificIndex, songs.indices.contains(specificIndex), songs[specificIndex].id == song.id {
            targetIndex = specificIndex
        } else if let found = songs.firstIndex(where: { $0.id == song.id }) {
            targetIndex = found
        } else {
            return
        }

        await removeSongFromPlaylist(playlistID: playlistID, at: targetIndex)
    }

    func removeSongFromCurrentPlaylist(_ song: SubsonicSong) async {
        guard let playlist = player.currentPlaylist else { return }
        await removeSong(song, from: playlist)
    }

    func duplicatePlaylist(_ playlist: PlaylistSummary) async {
        guard confirmOfflineAction() else { return }
        guard let client else { return }
        let songs = await playlistSongs(for: playlist)
        let newName = L10n.format("format.playlist.copyName", playlist.displayName)
        let created = try? await client.createPlaylist(name: newName, songIds: songs.map(\.id))
        if let id = created?.id, let comment = playlist.comment, !comment.isEmpty {
            try? await client.updatePlaylist(id: id, comment: comment)
        }
        await refreshPlaylists()
    }

    func deletePlaylist(_ playlist: PlaylistSummary) async {
        guard confirmOfflineAction() else { return }
        guard let client else { return }
        try? await client.deletePlaylist(id: playlist.id)
        if nav.selectedPlaylist?.id == playlist.id {
            nav.selected = .playlists
            nav.selectedPlaylist = nil
        }
        await refreshPlaylists()
    }
}
