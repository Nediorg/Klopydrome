import SwiftUI
import NavidromeClient

extension CommandPaletteView {
    var localItems: [CommandPaletteItem] {
        Self.makeLocalItems(for: app)
    }

    static func makeLocalItems(for app: AppState) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []
        items.append(contentsOf: makeNavigationItems(for: app))
        items.append(contentsOf: makeActionItems(for: app))
        items.append(contentsOf: makePlaylistItems(for: app))
        return items
    }

    private static func makeNavigationItems(for app: AppState) -> [CommandPaletteItem] {
        primaryNavigationItems(for: app) + secondaryNavigationItems(for: app)
    }

    private static func primaryNavigationItems(for app: AppState) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "nav_home",
                title: "Home".localized,
                subtitle: "Section".localized,
                icon: "house",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.home, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_recently_added",
                title: "Recently Added".localized,
                subtitle: "Section".localized,
                icon: "clock",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.recentlyAdded, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_artists",
                title: "Artists".localized,
                subtitle: "Section".localized,
                icon: "music.mic",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.artists, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_albums",
                title: "Albums".localized,
                subtitle: "Section".localized,
                icon: "square.stack",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.albums, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_songs",
                title: "Songs".localized,
                subtitle: "Section".localized,
                icon: "music.note",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.songs, in: app) }
            )
        ]
    }

    private static func secondaryNavigationItems(for app: AppState) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "nav_favorites",
                title: "Favorite".localized,
                subtitle: "Section".localized,
                icon: "star",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.favorites, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_playlists",
                title: "Playlists".localized,
                subtitle: "Section".localized,
                icon: "square.grid.3x3",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.playlists, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_genres",
                title: "Genres".localized,
                subtitle: "Section".localized,
                icon: "guitars",
                coverArt: nil,
                group: .navigation,
                action: { selectSection(.genres, in: app) }
            ),
            CommandPaletteItem(
                id: "nav_settings",
                title: "Settings".localized,
                subtitle: "Preferences".localized,
                icon: "gearshape",
                coverArt: nil,
                group: .navigation,
                action: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            )
        ]
    }

    private static func makeActionItems(for app: AppState) -> [CommandPaletteItem] {
        playbackActionItems(for: app) + panelActionItems(for: app) + managementActionItems(for: app)
    }

    private static func playbackActionItems(for app: AppState) -> [CommandPaletteItem] {
        let isPlaying = app.player.isPlaying
        return [
            CommandPaletteItem(
                id: "act_play_pause",
                title: (isPlaying ? "Pause" : "Play").localized,
                subtitle: app.player.displaySong?.displayTitle,
                icon: isPlaying ? "pause.fill" : "play.fill",
                coverArt: app.player.displaySong?.coverArt,
                group: .actions,
                action: { [weak app] in
                    app?.player.togglePlayPause()
                }
            ),
            CommandPaletteItem(
                id: "act_next",
                title: "Next Track".localized,
                subtitle: nil,
                icon: "forward.fill",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.player.next()
                }
            ),
            CommandPaletteItem(
                id: "act_prev",
                title: "Previous track".localized,
                subtitle: nil,
                icon: "backward.fill",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.player.previous()
                }
            )
        ]
    }

    private static func panelActionItems(for app: AppState) -> [CommandPaletteItem] {
        [
            CommandPaletteItem(
                id: "act_mini_player",
                title: "Mini Player".localized,
                subtitle: nil,
                icon: "pip",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.toggleMiniPlayer()
                }
            ),
            CommandPaletteItem(
                id: "act_queue",
                title: "Queue".localized,
                subtitle: nil,
                icon: "list.bullet",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.togglePlayerPanel(.queue)
                }
            ),
            CommandPaletteItem(
                id: "act_lyrics",
                title: "Lyrics".localized,
                subtitle: nil,
                icon: "quote.bubble",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.togglePlayerPanel(.lyrics)
                }
            )
        ]
    }

    private static func managementActionItems(for app: AppState) -> [CommandPaletteItem] {
        var list: [CommandPaletteItem] = [
            CommandPaletteItem(
                id: "act_new_playlist",
                title: "Create Playlist".localized,
                subtitle: nil,
                icon: "plus.rectangle.on.rectangle",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.openCreatePlaylist()
                }
            ),
            CommandPaletteItem(
                id: "act_new_smart_playlist",
                title: "New Smart Playlist".localized,
                subtitle: nil,
                icon: "gearshape.arrow.triangle.2.circlepath",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    app?.openSmartPlaylistEditor()
                }
            ),
            CommandPaletteItem(
                id: "act_scan_library",
                title: "Scan Media Library".localized,
                subtitle: nil,
                icon: "arrow.clockwise",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    Task { await app?.triggerServerScan() }
                }
            )
        ]
        list.append(contentsOf: makeServerProfileItems(for: app))
        return list
    }

    private static func makeServerProfileItems(for app: AppState) -> [CommandPaletteItem] {
        guard app.serverProfiles.count > 1 else { return [] }
        return app.serverProfiles.filter { $0.id != app.activeProfileID }.map { profile in
            CommandPaletteItem(
                id: "act_switch_profile_\(profile.id)",
                title: String(format: "Switch to %@".localized, profile.name),
                subtitle: profile.url,
                icon: "server.rack",
                coverArt: nil,
                group: .actions,
                action: { [weak app] in
                    Task { await app?.switchToProfile(profile) }
                }
            )
        }
    }

    private static func makePlaylistItems(for app: AppState) -> [CommandPaletteItem] {
        app.library.playlists.prefix(20).map { playlist in
            CommandPaletteItem(
                id: "playlist_\(playlist.id)",
                title: playlist.displayName,
                subtitle: "Playlist".localized,
                icon: "music.note.list",
                coverArt: playlist.coverArt,
                group: .playlists,
                action: { [weak app] in
                    app?.openPlaylist(playlist)
                }
            )
        }
    }

    private static func selectSection(_ section: NavigationState.Section, in app: AppState) {
        app.nav.selected = section
        app.nav.history.removeAll()
        app.nav.forwardHistory.removeAll()
        app.nav.navVersion += 1
    }
}
