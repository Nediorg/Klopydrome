import Foundation
import NavidromeClient

/// The observable snapshot of a single playlist request.
///
/// The same request owns the streamed header and song chunks for the detail
/// screen and for playback. Rows can therefore remain windowed in SwiftUI while
/// the completed song array is handed to Player as soon as it is available.
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
