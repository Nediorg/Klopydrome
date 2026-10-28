import SwiftUI
import NavidromeClient

struct AddToPlaylistMenu: View {
    var app: AppState?
    let songs: [SubsonicSong]
    var fetchSongs: (() async -> [SubsonicSong])? = nil

    @Environment(AppState.self) private var envApp

    private var resolvedApp: AppState {
        app ?? envApp
    }

    private var playlists: [PlaylistSummary] { resolvedApp.library.playlists }

    private func resolvedSongs() async -> [SubsonicSong] {
        if let fetchSongs {
            return await fetchSongs()
        }
        return songs
    }

    private func targetSongs(_ playlist: PlaylistSummary) async {
        let targets = await resolvedSongs()
        guard !targets.isEmpty else { return }
        guard resolvedApp.confirmOfflineAction() else { return }
        await resolvedApp.addSongsCheckingDuplicates(targets, to: playlist)
    }

    private func newPlaylist() async {
        let targets = await resolvedSongs()
        guard !targets.isEmpty else { return }
        guard resolvedApp.confirmOfflineAction() else { return }
        resolvedApp.presentInMainWindow {
            resolvedApp.creatingPlaylistSongs = targets
            resolvedApp.isCreatingPlaylist = true
        }
    }

    var body: some View {
        Menu {
            Button {
                Task { await newPlaylist() }
            } label: {
                Label("New Playlist".localized, systemImage: "plus.circle")
            }

            if !recent.isEmpty {
                Divider()
                Text("Recent".localized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(recent) { playlist in
                    Button(playlist.displayName) {
                        Task { await targetSongs(playlist) }
                    }
                }
            }

            if !playlists.isEmpty {
                Divider()
                if !recent.isEmpty {
                    Text("All Playlists".localized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                ForEach(playlists) { playlist in
                    Button(playlist.displayName) {
                        Task { await targetSongs(playlist) }
                    }
                }
            }
        } label: {
            Label("Add to Playlist".localized, systemImage: "text.badge.plus")
        }
    }

    private var recent: [PlaylistSummary] {
        let ids = resolvedApp.recentPlaylistIDs
        return playlists.filter { ids.contains($0.id) }.sorted { first, second in
            (ids.firstIndex(of: first.id) ?? .max) < (ids.firstIndex(of: second.id) ?? .max)
        }
    }
}