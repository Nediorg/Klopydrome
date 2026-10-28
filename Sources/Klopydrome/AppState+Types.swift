import Foundation
import NavidromeClient
import SwiftUI

enum StarKind: String, Codable, Sendable {
    case song, album, artist, playlist
}

protocol Starable {
    var id: String { get }
    var starred: String? { get }
    var starKind: StarKind { get }
}

extension SubsonicSong: Starable { var starKind: StarKind { .song } }
extension SubsonicAlbum: Starable { var starKind: StarKind { .album } }
extension Artist: Starable { var starKind: StarKind { .artist } }

enum PlaybackContext: Equatable {
    case playlist(PlaylistSummary)
    case smartPlaylist(SmartPlaylist)
    case album(SubsonicAlbum)
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System Default"
        case .dark: return "Dark Theme"
        case .light: return "Light Theme"
        }
    }
}

enum LyricsFontSize: String, Codable, CaseIterable, Identifiable {
    case standard, large, compact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .large: return "Large"
        case .compact: return "Compact"
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

enum LyricsAnimationMotion: String, Codable, CaseIterable, Identifiable {
    case smooth, subtle, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smooth: return "Smooth"
        case .subtle: return "Subtle"
        case .none: return "No Animation"
        }
    }
}

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

enum DuplicatePlaylistAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case ask
    case skip
    case allow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask".localized
        case .skip: return "Skip Duplicates".localized
        case .allow: return "Add Copies".localized
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
            case .home: return "Home".localized
            case .playlists: return "Playlists".localized
            case .recentlyAdded: return "Recently Added".localized
            case .songs: return "Songs".localized
            case .artists: return "Artists".localized
            case .albums: return "Albums".localized
            case .genres: return "Genres".localized
            case .favorites: return "Favorite".localized
            case .search: return "Search".localized
            }
        }

        var isSidebarRow: Bool { self != .search }
    }

    static let visibleLibrarySectionsKey = "VisibleLibrarySections"

    static let defaultVisibleLibrarySections: [Section] = [
        .recentlyAdded,
        .artists,
        .albums,
        .songs,
        .favorites
    ]

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

        var playlistID: String? {
            if case .playlist(let summary) = self { return summary.id }
            if case .smartPlaylist(let smart) = self { return smart.id }
            return nil
        }
    }

    var selected: Section = .home
    var navVersion = 0
    var history: [Destination] = []
    var selectedPlaylist: PlaylistSummary?
    var searchQuery: String = ""

    var visibleLibrarySections: Set<Section> = {
        guard let saved = UserDefaults.standard.stringArray(forKey: visibleLibrarySectionsKey) else {
            return Set(defaultVisibleLibrarySections)
        }
        let sections = saved.compactMap { Section(rawValue: $0) }
        return sections.isEmpty ? Set(defaultVisibleLibrarySections) : Set(sections)
    }()

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

struct SmartPlaylistEditorTarget: Identifiable {
    let id: String
    let playlist: SmartPlaylist?
    let server: ServerSmartPlaylist?

    init(playlist: SmartPlaylist? = nil, server: ServerSmartPlaylist? = nil) {
        self.id = server?.id ?? playlist?.id ?? UUID().uuidString
        self.playlist = playlist
        self.server = server
    }
}
