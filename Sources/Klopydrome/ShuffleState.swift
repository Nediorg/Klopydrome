import Foundation
import NavidromeClient

enum ShuffleMode: String, CaseIterable, Identifiable {
    case songs
    case albums
    case groups

    var id: String { rawValue }

    var label: String {
        switch self {
        case .songs: return "Songs"
        case .albums: return "Albums"
        case .groups: return "Groups"
        }
    }
}

@MainActor
final class ShuffleState {
    var mode: ShuffleMode = .songs
    var originalQueue: [SubsonicSong] = []
}
