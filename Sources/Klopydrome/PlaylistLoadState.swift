import Foundation
import NavidromeClient

/// The observable snapshot of a single playlist request.
///
/// The same request owns the streamed header and song chunks for the detail
/// screen and for playback. Rows can therefore remain windowed in SwiftUI while
/// the completed song array is handed to Player as soon as it is available.
struct PlaylistLoadState {
    let changed: String?
    let songCount: Int?
    var detail: PlaylistDetail?
    var songs: [SubsonicSong] = []
    var isLoading = false
    var isComplete = false
    var error: String?

    init(summary: PlaylistSummary) {
        changed = summary.changed
        songCount = summary.songCount
    }

    func matches(_ summary: PlaylistSummary) -> Bool {
        changed == summary.changed && songCount == summary.songCount
    }
}
