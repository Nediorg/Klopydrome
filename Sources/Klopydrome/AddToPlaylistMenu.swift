import SwiftUI
import NavidromeClient

/// Inline submenu for picking a destination playlist for one or more songs,
/// modelled after Apple Music: a "Новый плейлист" action, then recently-used
/// playlists, then the full playlists list. Selecting a playlist adds the
/// songs immediately; "Новый плейлист" opens a creation sheet.
///
/// Songs can be supplied directly (`songs`) or fetched lazily (`fetchSongs`),
/// so an album or other non-song target can reuse the exact same picker UI.
struct AddToPlaylistMenu: View {
    @Environment(AppState.self) private var app
    let songs: [SubsonicSong]
    var fetchSongs: (() async -> [SubsonicSong])? = nil

    private var playlists: [PlaylistSummary] { app.library.playlists }

    private func resolvedSongs() async -> [SubsonicSong] {
        if let fetchSongs {
            return await fetchSongs()
        }
        return songs
    }

    private func targetSongs(_ playlist: PlaylistSummary) async {
        let targets = await resolvedSongs()
        guard !targets.isEmpty else { return }
        await app.addToPlaylist(targets, playlistID: playlist.id)
    }

    private func newPlaylist() async {
        let targets = await resolvedSongs()
        guard !targets.isEmpty else { return }
        // The creation sheet is attached to the main window; from the mini
        // player it must present there after focus returns (see
        // `AppState.presentInMainWindow`).
        app.presentInMainWindow {
            app.creatingPlaylistSongs = targets
            app.isCreatingPlaylist = true
        }
    }

    var body: some View {
        Menu {
            Button {
                Task { await newPlaylist() }
            } label: {
                Label("Новый плейлист", systemImage: "plus.circle")
            }

            if !recent.isEmpty {
                Divider()
                Text("Недавние".localized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(recent) { playlist in
                    Button(playlist.displayName) {
                        Task { await targetSongs(playlist) }
                    }
                }
            }

            Divider()
            Text("Все плейлисты".localized)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(others) { playlist in
                Button(playlist.displayName) {
                    Task { await targetSongs(playlist) }
                }
            }
        } label: {
            Label("Добавить в плейлист", systemImage: "text.badge.plus")
        }
    }

    private var recents: [PlaylistSummary] {
        let ids = app.recentPlaylistIDs
        return playlists.filter { ids.contains($0.id) }
    }

    private var recent: [PlaylistSummary] {
        let ids = app.recentPlaylistIDs
        return recents.sorted { a, b in
            (ids.firstIndex(of: a.id) ?? .max) < (ids.firstIndex(of: b.id) ?? .max)
        }
    }

    private var others: [PlaylistSummary] {
        playlists.filter { !app.recentPlaylistIDs.contains($0.id) }
    }
}