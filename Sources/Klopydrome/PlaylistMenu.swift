import SwiftUI
import NavidromeClient

struct PlaylistContextMenuItems: View {
    @Environment(AppState.self) private var app
    let playlist: PlaylistSummary

    var onRename: () -> Void = {}
    var onEditRules: () -> Void = {}
    var onDelete: () -> Void = {}

    private var hasSongs: Bool { (playlist.songCount ?? 0) > 0 }
    private var followed: Bool { app.isFollowed(playlist) }

    var body: some View {
        Button("Edit…".localized) {
            guard app.confirmOfflineAction() else { return }
            onRename()
        }
        if playlist.isSmart {
            Button("Edit Rules…".localized) {
                guard app.confirmOfflineAction() else { return }
                onEditRules()
            }
        }

        if hasSongs {
            Divider()
            Button(L10n.format("format.playlist.play", playlist.displayName)) {
                Task { await app.play(playlist) }
            }
            Button(L10n.format("format.playlist.shuffle", playlist.displayName)) {
                Task { await app.playShuffled(playlist) }
            }
            Button("Play Next".localized) {
                Task { await app.playNext(playlist) }
            }
            Button("Play Later".localized) {
                Task { await app.playLater(playlist) }
            }
        }

        Divider()
        Button((followed ? "Unstar" : "Star").localized) {
            app.toggleFollow(playlist)
        }
        Button((playlist.isPublic == true ? "Make Private" : "Make Public").localized) {
            guard app.confirmOfflineAction() else { return }
            Task { await app.togglePlaylistVisibility(playlist) }
        }

        Divider()
        if app.isPlaylistDownloading(playlist.id) {
            Button("Cancel Download".localized) {
                app.cancelPlaylistDownload(playlist.id)
            }
        } else {
            Button("Download Playlist".localized) {
                app.cachePlaylist(playlist)
            }
            .disabled(app.isOfflineSession)
        }
        Divider()
        Button("Duplicate".localized) {
            guard app.confirmOfflineAction() else { return }
            Task { await app.duplicatePlaylist(playlist) }
        }
        Button("Share…".localized) {
            app.presentShare(ShareTarget(entityID: playlist.id, title: playlist.displayName, kind: .playlist))
        }
        Divider()
        Button("Delete from Library".localized, role: .destructive) {
            guard app.confirmOfflineAction() else { return }
            onDelete()
        }
    }
}

extension PlaylistDetail {
    var summary: PlaylistSummary {
        PlaylistSummary(id: id, name: name, comment: comment, owner: owner,
                        coverArt: coverArt, songCount: songCount, duration: duration,
                        created: created, changed: changed, isPublic: isPublic,
                        isReadonly: isReadonly, validUntil: validUntil)
    }
}

extension AppState {
    func togglePlaylistVisibility(_ playlist: PlaylistSummary) async {
        guard let client else { return }
        try? await client.updatePlaylist(id: playlist.id, isPublic: !(playlist.isPublic ?? false))
        invalidatePlaylistDetail(for: playlist.id)
        await refreshPlaylists()
        if let updated = library.playlists.first(where: { $0.id == playlist.id }) {
            await reloadPlaylist(updated)
        }
    }
}

struct SmartPlaylistContextMenuItems: View {
    @Environment(AppState.self) private var app
    let playlist: SmartPlaylist

    var onEditRules: () -> Void = {}
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    private func playable(_ songs: [SubsonicSong], _ action: ([SubsonicSong]) -> Void) {
        guard !songs.isEmpty else { return }
        action(songs)
    }

    var body: some View {
        Button("Edit…".localized) { onRename() }
        Button("Edit Rules…".localized) { onEditRules() }

        Divider()
        Button(L10n.format("format.playlist.play", playlist.name)) {
            Task {
                if let songs = try? await app.computeSmartPlaylist(playlist) {
                    playable(songs) { app.play($0, at: 0, context: .smartPlaylist(playlist)) }
                }
            }
        }
        Button(L10n.format("format.playlist.shuffle", playlist.name)) {
            Task {
                if let songs = try? await app.computeSmartPlaylist(playlist) {
                    playable(songs) { app.playShuffled($0, context: .smartPlaylist(playlist)) }
                }
            }
        }

        Divider()
        Button("Share…".localized) {
            app.presentShare(ShareTarget(entityID: playlist.id, title: playlist.name, kind: .playlist))
        }
        Divider()
        Button("Delete".localized, role: .destructive) { onDelete() }
    }
}
