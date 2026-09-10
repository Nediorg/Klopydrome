import Foundation
import NavidromeClient

enum ShuffleMode: String, CaseIterable, Identifiable {
    case songs
    case albums
    case groups

    var id: String { rawValue }

    var label: String {
        switch self {
        case .songs: return "Песни"
        case .albums: return "Альбомы"
        case .groups: return "Группы"
        }
    }
}

/// State retained while a queue is shuffled, so disabling shuffle can restore
/// its original order without disturbing the current track.
@MainActor
final class ShuffleState {
    var mode: ShuffleMode = .songs
    var originalQueue: [SubsonicSong] = []
    var shuffledQueue: [SubsonicSong] = []
}
