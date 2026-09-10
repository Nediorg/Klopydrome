import Foundation
import NavidromeClient
import SwiftUI

/// Subsonic star endpoint names entities by a *type-specific* id list
/// (songIds / albumIds / artistIds). This lets client code star any entity
/// without branching on concrete types everywhere.
enum StarKind {
    case song, album, artist
}

/// Anything that can be starred (songs, albums, artists): stable `id` plus the
/// server `starred` snapshot and the entity kind used for the API call.
protocol Starable {
    var id: String { get }
    var starred: String? { get }
    var starKind: StarKind { get }
}

extension SubsonicSong: Starable { var starKind: StarKind { .song } }
extension SubsonicAlbum: Starable { var starKind: StarKind { .album } }
extension Artist: Starable { var starKind: StarKind { .artist } }

/// Appearance preference (GUIDELINES §16): follow the system or force dark/light.
enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Как в системе"
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        }
    }
}

/// Audio rendering backend. MPV (libmpv, via MPVKit) decodes every format the
/// server can send and seeks HTTP streams sample-accurately by range-requesting
/// the exact byte offset, so lyric highlights stay locked to the audio.
/// AVFoundation is kept as an opt-out for tracks mpv's build doesn't cover.
enum PlaybackEngine: String, CaseIterable, Identifiable {
    case mpv
    case avFoundation
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mpv: return "MPV (рекомендуется)"
        case .avFoundation: return "AVFoundation"
        }
    }
}

struct NavigationState {
    enum Section: String, Hashable, CaseIterable {
        case home = "Home"
        case playlists = "Playlists"
        case recentlyAdded = "Recently Added"
        case songs = "Songs"
        case artists = "Artists"
        case albums = "Albums"
        case favorites = "Favorites"
        case search = "Search"

        var icon: String {
            switch self {
            case .home: return "house"
            case .playlists: return "square.grid.3x3"
            case .recentlyAdded: return "clock"
            case .songs: return "music.note"
            case .artists: return "music.mic"
            case .albums: return "square.stack"
            case .favorites: return "heart"
            case .search: return "magnifyingglass"
            }
        }

        /// Sections shown as real rows in the sidebar (search is driven by the search field).
        var isSidebarRow: Bool { self != .search }
    }

    var selected: Section = .home
    /// Monotonic counter bumped whenever the user explicitly selects a sidebar
    /// row, even the one already active. The detail view observes this to pop
    /// its navigation stack to the selected section's root on every click —
    /// without it, re-clicking "Главная" (or a playlist) while a sub-page such
    /// as an album card is open would leave the stack untouched.
    var navVersion = 0
    /// Album requested by a surface outside the main navigation stack, such as
    /// the mini-player. `DetailView` consumes this request exactly once.
    var pendingAlbum: SubsonicAlbum?
    /// Song whose detail page was requested by a surface outside the main
    /// navigation stack (the mini-player has no stack of its own).
    /// `DetailView` consumes this request exactly once, mirroring `pendingAlbum`.
    var pendingSong: SubsonicSong?
    /// Artist requested from a song row's title/subtitle menu.
    var pendingArtist: Artist?
    /// Playlist picked directly from the sidebar; shown in the detail column
    /// instead of the "All Playlists" grid.
    var selectedPlaylist: PlaylistSummary?
    var searchQuery: String = ""
}
