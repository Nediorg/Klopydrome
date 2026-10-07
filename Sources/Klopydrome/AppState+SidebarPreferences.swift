import Foundation
import NavidromeClient

extension AppState {
    /// Toggles the enabled state of a library section in the sidebar.
    /// If the currently active section is toggled off, automatically redirects
    /// navigation to the first available section or Home to avoid dead ends.
    func toggleLibrarySection(_ section: NavigationState.Section) {
        nav.toggleLibrarySection(section)
        if !nav.visibleLibrarySections.contains(nav.selected) &&
            NavigationState.customizableLibrarySections.contains(nav.selected) {
            if let first = NavigationState.customizableLibrarySections.first(where: {
                nav.visibleLibrarySections.contains($0)
            }) {
                nav.selected = first
            } else {
                nav.selected = .home
            }
        }
    }

    /// Opens a specific genre in the main library detail view.
    func openGenre(_ genreName: String) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.genre(genreName))
        nav.navVersion += 1
    }

    /// Groups downloaded songs into genre summaries for offline navigation.
    func offlineGenres(from songs: [SubsonicSong]) -> [Genre] {
        var counts: [String: Int] = [:]
        for song in songs {
            guard let rawGenre = song.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawGenre.isEmpty else {
                continue
            }
            counts[rawGenre, default: 0] += 1
        }
        return counts.map { name, count in
            Genre(value: name, songCount: count, albumCount: nil)
        }
    }
}
