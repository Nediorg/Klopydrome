import Foundation
import NavidromeClient

// MARK: - Playlist actions

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

    /// Moves a playlist to the front of the "recent" list used by the
    /// "Добавить в плейлист" submenu and Quick Access.
    func recordRecentPlaylist(_ id: String) {
        var recent = recentPlaylistIDs
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recentPlaylistIDs = Array(recent.prefix(10))
    }

    /// Reloads the sidebar playlist manifest from the server.
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

    /// Returns a full playlist response only while it agrees with the current
    /// lightweight playlist manifest.
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
        Task { [weak self] in
            await self?.cache?.removeFile(for: .metadata, key: "detail_playlist_\(playlistID)")
        }
    }

    /// Duplicates a playlist under a new name.
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
