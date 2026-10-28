import Foundation
import NavidromeClient

struct PlaylistLoadState {
    var changed: String?
    var songCount: Int?
    var detail: PlaylistDetail?
    var songs: [SubsonicSong] = []
    var isLoading = false
    var isSyncing = false
    var isComplete = false
    var error: String?

    init(summary: PlaylistSummary, existing: PlaylistLoadState? = nil) {
        changed = summary.changed
        songCount = summary.songCount
        detail = existing?.detail
        songs = existing?.songs ?? []
    }

    func matches(_ summary: PlaylistSummary) -> Bool {
        isComplete && !songs.isEmpty && changed == summary.changed && songCount == summary.songCount
    }
}
