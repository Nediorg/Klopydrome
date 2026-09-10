import Foundation
import NavidromeClient

extension AppState {
    // MARK: Smart playlists

    func loadSmartPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: smartPlaylistsKey),
              let decoded = try? JSONDecoder().decode([SmartPlaylist].self, from: data) else {
            return
        }
        smartPlaylists = decoded
    }

    func saveSmartPlaylists() {
        guard let data = try? JSONEncoder().encode(smartPlaylists) else { return }
        UserDefaults.standard.set(data, forKey: smartPlaylistsKey)
    }

    func upsertSmartPlaylist(_ playlist: SmartPlaylist) {
        if let index = smartPlaylists.firstIndex(where: { $0.id == playlist.id }) {
            smartPlaylists[index] = playlist
        } else {
            smartPlaylists.append(playlist)
        }
        saveSmartPlaylists()
    }

    func deleteSmartPlaylist(id: String) {
        smartPlaylists.removeAll { $0.id == id }
        saveSmartPlaylists()
    }

    func renameSmartPlaylist(id: String, name: String) {
        guard let index = smartPlaylists.firstIndex(where: { $0.id == id }) else { return }
        smartPlaylists[index].name = name
        saveSmartPlaylists()
    }

    // MARK: Followed playlists (local favourites)

    func loadFollowedPlaylists() {
        guard let ids = UserDefaults.standard.stringArray(forKey: followedKey) else { return }
        followedPlaylistIDs = Set(ids)
    }

    func saveFollowedPlaylists() {
        UserDefaults.standard.set(Array(followedPlaylistIDs).sorted(), forKey: followedKey)
    }

    func isFollowed(_ playlist: PlaylistSummary) -> Bool {
        followedPlaylistIDs.contains(playlist.id)
    }

    func isFollowed(_ playlist: PlaylistDetail) -> Bool {
        followedPlaylistIDs.contains(playlist.id)
    }

    func toggleFollow(_ playlist: PlaylistSummary) {
        if followedPlaylistIDs.contains(playlist.id) {
            followedPlaylistIDs.remove(playlist.id)
        } else {
            followedPlaylistIDs.insert(playlist.id)
        }
    }

    func toggleFollow(_ playlist: PlaylistDetail) {
        if followedPlaylistIDs.contains(playlist.id) {
            followedPlaylistIDs.remove(playlist.id)
        } else {
            followedPlaylistIDs.insert(playlist.id)
        }
    }

    /// Queries the server per the playlist's rules and returns matching songs.
    /// Serialized over to work from a detail view or preview.
    func computeSmartPlaylist(_ playlist: SmartPlaylist) async throws -> [SubsonicSong] {
        guard let engine = smartPlaylistEngine else {
            throw SmartPlaylistError.notConnected
        }
        return try await engine.compute(playlist)
    }

    /// Preview a query-tree (AST) without saving: evaluates the predicate
    /// against the full-library pool honored by the engine.
    func previewSmartQuery(_ query: SmartQuery) async throws -> [SubsonicSong] {
        guard let engine = smartPlaylistEngine else {
            throw SmartPlaylistError.notConnected
        }
        return try await engine.preview(query)
    }
}
