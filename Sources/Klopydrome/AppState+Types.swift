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

/// Visual scale of synchronized lyrics lines.
enum LyricsFontSize: String, Codable, CaseIterable, Identifiable {
    case standard, large, compact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Обычный"
        case .large: return "Крупный"
        case .compact: return "Компактный"
        }
    }
    var font: Font {
        switch self {
        case .standard: return .system(.title3, design: .default).weight(.semibold)
        case .large: return .system(.title2, design: .default).weight(.semibold)
        case .compact: return .system(.body, design: .default).weight(.semibold)
        }
    }
}

/// Motion and ripple physics style for lyrics advancement.
enum LyricsAnimationMotion: String, Codable, CaseIterable, Identifiable {
    case smooth, subtle, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smooth: return "Плавная"
        case .subtle: return "Мягкая"
        case .none: return "Без анимации"
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
        case .mpv: return "MPV"
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
        case genres = "Genres"
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
            case .genres: return "guitars"
            case .favorites: return "star"
            case .search: return "magnifyingglass"
            }
        }

        var title: String {
            switch self {
            case .home: return "Главная".localized
            case .playlists: return "Плейлисты".localized
            case .recentlyAdded: return "Недавно добавленные".localized
            case .songs: return "Песни".localized
            case .artists: return "Артисты".localized
            case .albums: return "Альбомы".localized
            case .genres: return "Жанры".localized
            case .favorites: return "Избранное".localized
            case .search: return "Поиск".localized
            }
        }

        /// Sections shown as real rows in the sidebar (search is driven by the search field).
        var isSidebarRow: Bool { self != .search }
    }

    /// Key used to persist the user's enabled library sections.
    static let visibleLibrarySectionsKey = "VisibleLibrarySections"

    /// Default set of sections shown under the "Медиатека" header.
    static let defaultVisibleLibrarySections: [Section] = [
        .recentlyAdded,
        .artists,
        .albums,
        .songs,
        .favorites
    ]

    /// All configurable sections available under the "Медиатека" header.
    static let customizableLibrarySections: [Section] = [
        .recentlyAdded,
        .artists,
        .albums,
        .songs,
        .genres,
        .favorites
    ]

    enum Destination: Hashable {
        case album(SubsonicAlbum)
        case playlist(PlaylistSummary)
        case smartPlaylist(SmartPlaylist)
        case artist(Artist)
        case song(SubsonicSong)
        case genre(String)
    }

    var selected: Section = .home
    /// Monotonic counter bumped whenever the user explicitly selects a sidebar
    /// row, even the one already active.
    var navVersion = 0
    /// Sub-pages opened in the detail column (albums, artists, playlists, songs).
    /// Pushed pages stack on top of each other and can be popped via the back button
    /// or cleared by clicking a sidebar item.
    var history: [Destination] = []
    /// Playlist picked directly from the sidebar; shown in the detail column
    /// instead of the "All Playlists" grid.
    var selectedPlaylist: PlaylistSummary?
    var searchQuery: String = ""

    /// Active set of library sections shown in the sidebar.
    var visibleLibrarySections: Set<Section> = {
        guard let saved = UserDefaults.standard.stringArray(forKey: visibleLibrarySectionsKey) else {
            return Set(defaultVisibleLibrarySections)
        }
        let sections = saved.compactMap { Section(rawValue: $0) }
        return sections.isEmpty ? Set(defaultVisibleLibrarySections) : Set(sections)
    }()

    /// Toggles visibility of a library section, keeping at least one active.
    mutating func toggleLibrarySection(_ section: Section) {
        if visibleLibrarySections.contains(section) {
            guard visibleLibrarySections.count > 1 else { return }
            visibleLibrarySections.remove(section)
        } else {
            visibleLibrarySections.insert(section)
        }
        UserDefaults.standard.set(
            visibleLibrarySections.map(\.rawValue),
            forKey: Self.visibleLibrarySectionsKey
        )
    }
}
