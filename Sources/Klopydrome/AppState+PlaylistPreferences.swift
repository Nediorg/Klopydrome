import Foundation
import NavidromeClient

extension AppState {

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

    func toggleFollow(_ playlist: PlaylistSummary, skipOfflineConfirm: Bool = false) {
        toggleFollow(id: playlist.id, skipOfflineConfirm: skipOfflineConfirm)
    }

    func toggleFollow(_ playlist: PlaylistDetail, skipOfflineConfirm: Bool = false) {
        toggleFollow(id: playlist.id, skipOfflineConfirm: skipOfflineConfirm)
    }

    func toggleFollow(id: String, skipOfflineConfirm: Bool = false) {
        if !skipOfflineConfirm, !confirmOfflineAction() { return }
        let willFollow = !followedPlaylistIDs.contains(id)
        if willFollow {
            followedPlaylistIDs.insert(id)
        } else {
            followedPlaylistIDs.remove(id)
        }
        if isOfflineSession {
            queueOfflineStar(id: id, kind: .playlist, isStarred: willFollow)
        }
    }

    func previewSmartQuery(_ query: SmartQuery) async throws -> [SubsonicSong] {
        guard let engine = smartPlaylistEngine else {
            throw SmartPlaylistError.notConnected
        }
        return try await engine.preview(query)
    }
}
