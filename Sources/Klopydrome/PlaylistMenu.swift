import SwiftUI
import NavidromeClient

/// Apple-Music-style context menu for a playlist. This is the single source of
/// truth for playlist actions — the sidebar rows, the playlists grid tiles and
/// the detail-window «…» button all build their menus from this component so
/// the offered actions can never drift apart.
///
/// Actions depend on whether the playlist has any songs (an empty playlist only
/// exposes Edit / Follow / Public / Duplicate / Delete, mirroring Apple Music).
///
/// Excluded (tied to iTunes/Apple-only or not applicable):
/// «Не нравится», «Открыть в новом окне», «Записать на диск».
struct PlaylistContextMenuItems: View {
    @Environment(AppState.self) private var app
    let playlist: PlaylistSummary

    /// Callbacks wired to the host view so it can present chrome UIs.
    var onRename: () -> Void = {}
    var onEditRules: () -> Void = {}
    var onDelete: () -> Void = {}

    private var hasSongs: Bool { (playlist.songCount ?? 0) > 0 }
    private var followed: Bool { app.isFollowed(playlist) }

    var body: some View {
        Button("Изменить…") { onRename() }
        if playlist.isSmart {
            Button("Редактировать правила…") { onEditRules() }
        }

        if hasSongs {
            Divider()
            Button(L10n.format("format.playlist.play", playlist.displayName)) {
                Task { await app.play(playlist) }
            }
            Button(L10n.format("format.playlist.shuffle", playlist.displayName)) {
                Task { await app.playShuffled(playlist) }
            }
            Button("Слушать следующей") {
                Task { await app.playNext(playlist) }
            }
            Button("В конец очереди") {
                Task { await app.playLater(playlist) }
            }
        }

        Divider()
        Button(followed ? "Убрать из избранного" : "Добавить в избранное") {
            app.toggleFollow(playlist)
        }
        Button(playlist.isPublic == true ? "Сделать закрытым" : "Сделать открытым") {
            Task { await app.togglePlaylistVisibility(playlist) }
        }

        Divider()
        Button("Загрузить плейлист") {
            app.cachePlaylist(playlist)
        }
        Divider()
        Button("Дублировать") {
            Task { await app.duplicatePlaylist(playlist) }
        }
        Button("Поделиться…") {
            app.presentShare(ShareTarget(entityID: playlist.id, title: playlist.displayName, kind: .playlist))
        }
        Divider()
        Button("Удалить из медиатеки", role: .destructive) { onDelete() }
    }
}

extension PlaylistDetail {
    /// The same playlist as its summary form so the shared menu component can
    /// operate on it unchanged.
    var summary: PlaylistSummary {
        PlaylistSummary(id: id, name: name, comment: comment, owner: owner,
                        coverArt: coverArt, songCount: songCount, duration: duration,
                        created: created, changed: changed, isPublic: isPublic,
                        isReadonly: isReadonly, validUntil: validUntil)
    }
}

extension AppState {
    /// Flips a playlist's public/private flag. Lives next to the shared menu so
    /// the toggle is the single place the flag is mutated from any surface.
    func togglePlaylistVisibility(_ playlist: PlaylistSummary) async {
        guard let client else { return }
        try? await client.updatePlaylist(id: playlist.id, isPublic: !(playlist.isPublic ?? false))
        await refreshPlaylists()
    }
}

/// Apple-Music-style context menu for a smart playlist. Single source of truth
/// for smart-playlist actions — the playlists-grid tiles, the sidebar row men
/// and the detail window's «…» button all build from this, so the offered
/// actions never drift apart. Actions that need host chrome (rename, delete,
/// rule editing) are wired through callbacks.
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
        Button("Изменить…") { onRename() }
        Button("Редактировать правила…") { onEditRules() }

        Divider()
        Button(L10n.format("format.playlist.play", playlist.name)) {
            Task {
                if let songs = try? await app.computeSmartPlaylist(playlist) {
                    playable(songs) { app.play($0, at: 0) }
                }
            }
        }
        Button(L10n.format("format.playlist.shuffle", playlist.name)) {
            Task {
                if let songs = try? await app.computeSmartPlaylist(playlist) {
                    playable(songs) { app.playShuffled($0) }
                }
            }
        }

        Divider()
        Button("Поделиться…") {
            app.presentShare(ShareTarget(entityID: playlist.id, title: playlist.name, kind: .playlist))
        }
        Divider()
        Button("Удалить", role: .destructive) { onDelete() }
    }
}
