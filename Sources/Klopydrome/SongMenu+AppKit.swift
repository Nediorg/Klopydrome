import AppKit
import Foundation
import NavidromeClient

// MARK: - AppKit On-Demand Context Menu

/// Surface-specific prefix action for song menus (e.g. «Убрать из плейлиста»).
public struct SongMenuExtraAction {
    public let title: String
    public let systemImage: String?
    public let action: () -> Void

    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

@MainActor
final class SongMenuActionItem: NSMenuItem, NSMenuItemValidation {
    private let handler: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.handler = action
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        self.target = self
        self.isEnabled = isEnabled
        if let systemImage {
            self.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return isEnabled
    }

    @objc private func performAction() {
        handler()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Menu Builders

@MainActor
enum SongActionMenuBuilder {
    static func addPlaybackItems(
        to menu: NSMenu,
        targets: [SubsonicSong],
        app: AppState,
        isPlayableOffline: Bool,
        onPlay: (() -> Void)?
    ) {
        if let onPlay {
            menu.addItem(SongMenuActionItem(
                title: "Слушать".localized,
                systemImage: "play.fill",
                isEnabled: isPlayableOffline,
                action: onPlay
            ))
        }
        menu.addItem(SongMenuActionItem(
            title: "Слушать следующей".localized,
            systemImage: "text.line.first.and.arrowtriangle.forward",
            isEnabled: isPlayableOffline
        ) {
            targets.forEach { app.playNext($0) }
        })
        menu.addItem(SongMenuActionItem(
            title: "В конец очереди".localized,
            systemImage: "text.line.last.and.arrowtriangle.forward",
            isEnabled: isPlayableOffline
        ) {
            targets.forEach { app.playLater($0) }
        })
    }

    static func addPlaylistSubmenu(
        to menu: NSMenu,
        targets: [SubsonicSong],
        app: AppState
    ) {
        let playlistMenu = NSMenu(title: "Добавить в плейлист".localized)
        playlistMenu.autoenablesItems = false
        playlistMenu.addItem(SongMenuActionItem(
            title: "Новый плейлист".localized,
            systemImage: "plus.circle"
        ) {
            guard app.confirmOfflineAction() else { return }
            app.presentInMainWindow {
                app.creatingPlaylistSongs = targets
                app.isCreatingPlaylist = true
            }
        })

        let playlists = app.library.playlists
        let recentIDs = app.recentPlaylistIDs
        let recents = playlists.filter { recentIDs.contains($0.id) }.sorted { firstPlaylist, secondPlaylist in
            (recentIDs.firstIndex(of: firstPlaylist.id) ?? .max) < (recentIDs.firstIndex(of: secondPlaylist.id) ?? .max)
        }
        if !recents.isEmpty {
            playlistMenu.addItem(.separator())
            let header = NSMenuItem(title: "Недавние".localized, action: nil, keyEquivalent: "")
            header.isEnabled = false
            playlistMenu.addItem(header)
            for playlist in recents {
                playlistMenu.addItem(SongMenuActionItem(title: playlist.displayName) {
                    guard app.confirmOfflineAction() else { return }
                    Task { await app.addSongsCheckingDuplicates(targets, to: playlist) }
                })
            }
        }

        if !playlists.isEmpty {
            playlistMenu.addItem(.separator())
            if !recents.isEmpty {
                let header = NSMenuItem(title: "Все плейлисты".localized, action: nil, keyEquivalent: "")
                header.isEnabled = false
                playlistMenu.addItem(header)
            }
            for playlist in playlists {
                playlistMenu.addItem(SongMenuActionItem(title: playlist.displayName) {
                    guard app.confirmOfflineAction() else { return }
                    Task { await app.addSongsCheckingDuplicates(targets, to: playlist) }
                })
            }
        }

        let parentItem = NSMenuItem(title: "Добавить в плейлист".localized, action: nil, keyEquivalent: "")
        parentItem.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: nil)
        parentItem.submenu = playlistMenu
        menu.addItem(parentItem)
    }

    static func addFavoriteAndDownloadItems(
        to menu: NSMenu,
        song: SubsonicSong,
        targets: [SubsonicSong],
        app: AppState
    ) {
        let isStarred = app.isStarred(song)
        let primaryCached = targets.count > 1
            ? targets.allSatisfy { app.isCached($0) }
            : app.isCached(song)
        let primaryDownloading = targets.count > 1
            ? targets.allSatisfy { app.downloadingSongIDs.contains($0.id) }
            : app.downloadingSongIDs.contains(song.id)

        menu.addItem(SongMenuActionItem(
            title: (isStarred ? "Убрать из избранного" : "В избранное").localized,
            systemImage: isStarred ? "star.slash" : "star"
        ) {
            guard app.confirmOfflineAction() else { return }
            targets.forEach { app.toggleStar($0, skipOfflineConfirm: true) }
        })

        if primaryDownloading {
            menu.addItem(SongMenuActionItem(
                title: "Отменить загрузку".localized,
                systemImage: "xmark.circle"
            ) {
                targets.forEach { app.cancelSongDownload($0) }
            })
        } else {
            let title = (primaryCached ? "Удалить загрузку" : "Загрузить").localized
            let systemImage = primaryCached ? "trash" : "arrow.down.circle"
            menu.addItem(SongMenuActionItem(
                title: title,
                systemImage: systemImage,
                isEnabled: !app.isOfflineSession || primaryCached
            ) {
                if primaryCached {
                    targets.forEach { targetSong in Task { await app.removeFromCache(targetSong) } }
                } else {
                    app.cacheSongs(targets)
                }
            })
        }
        menu.addItem(SongMenuActionItem(
            title: "Скачать".localized,
            systemImage: "arrow.down",
            isEnabled: !app.isOfflineSession || primaryCached
        ) {
            app.downloadTrack(song)
        })
    }

    static func addRatingSubmenu(
        to menu: NSMenu,
        song: SubsonicSong,
        targets: [SubsonicSong],
        app: AppState
    ) {
        let rateMenu = NSMenu(title: "Оценить".localized)
        rateMenu.autoenablesItems = false
        let currentRating = app.effectiveRating(for: song)
        for star in 1...5 {
            let item = SongMenuActionItem(title: "\(star) \(Pluralized.star(star))") {
                guard app.confirmOfflineAction() else { return }
                targets.forEach {
                    app.setRating(
                        star == app.effectiveRating(for: $0) ? 0 : star,
                        for: $0,
                        skipOfflineConfirm: true
                    )
                }
            }
            if star == currentRating {
                item.state = .on
            }
            rateMenu.addItem(item)
        }
        let parentItem = NSMenuItem(title: "Оценить".localized, action: nil, keyEquivalent: "")
        parentItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        parentItem.submenu = rateMenu
        menu.addItem(parentItem)
    }

    static func addNavigationItems(
        to menu: NSMenu,
        song: SubsonicSong,
        app: AppState
    ) {
        menu.addItem(SongMenuActionItem(
            title: "Создать станцию".localized,
            systemImage: "dot.radiowaves.left.and.right",
            isEnabled: !app.isOfflineSession
        ) {
            app.playStation(from: song)
        })

        if let albumId = song.albumId {
            menu.addItem(SongMenuActionItem(
                title: "Показать альбом в медиатеке".localized,
                systemImage: "square.stack"
            ) {
                app.openAlbumInLibrary(.nowPlayingSummary(from: song, albumID: albumId))
            })
        }

        let collaborators = SongCollaborators.parse(from: song, library: app.library)
        if collaborators.count > 1 {
            let parentItem = NSMenuItem(title: "Перейти к исполнителю".localized, action: nil, keyEquivalent: "")
            parentItem.image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: nil)
            let subMenu = NSMenu()
            subMenu.autoenablesItems = false
            for artist in collaborators {
                subMenu.addItem(SongMenuActionItem(title: artist.name) {
                    app.openArtistInLibrary(artist)
                })
            }
            parentItem.submenu = subMenu
            menu.addItem(parentItem)
        } else if let singleArtist = collaborators.first {
            menu.addItem(SongMenuActionItem(
                title: "Перейти к исполнителю".localized,
                systemImage: "music.mic"
            ) {
                app.openArtistInLibrary(singleArtist)
            })
        }

        addPlaylistNavigationItem(to: menu, app: app)
    }

    private static func addPlaylistNavigationItem(to menu: NSMenu, app: AppState) {
        if let playerPlaylist = app.player.currentPlaylist {
            menu.addItem(SongMenuActionItem(
                title: "Перейти к плейлисту".localized,
                systemImage: "music.note.list"
            ) {
                app.openPlaylist(playerPlaylist)
            })
        } else if case .smartPlaylist(let smart) = app.player.playbackContext {
            menu.addItem(SongMenuActionItem(
                title: "Перейти к плейлисту".localized,
                systemImage: "gearshape"
            ) {
                app.openSmartPlaylist(smart)
            })
        }
    }

    static func addMetadataItems(
        to menu: NSMenu,
        song: SubsonicSong,
        app: AppState
    ) {
        menu.addItem(SongMenuActionItem(
            title: "Свойства…".localized,
            systemImage: "info.circle"
        ) {
            app.inspectSong(song)
        })

        menu.addItem(SongMenuActionItem(
            title: "Скопировать".localized,
            systemImage: "doc.on.doc"
        ) {
            let parts = [song.displayTitle, song.artist, song.album].compactMap { $0 }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(parts.joined(separator: " — "), forType: .string)
        })

        menu.addItem(SongMenuActionItem(
            title: "Поделиться…".localized,
            systemImage: "square.and.arrow.up"
        ) {
            app.presentShare(ShareTarget(entityID: song.id, title: song.displayTitle, kind: .song))
        })
    }
}

// MARK: - Secondary & Playlist Actions

extension SongActionMenuBuilder {
    static func addExtraActions(to menu: NSMenu, extraActions: [SongMenuExtraAction]) {
        guard !extraActions.isEmpty else { return }
        for extra in extraActions {
            menu.addItem(SongMenuActionItem(
                title: extra.title,
                systemImage: extra.systemImage,
                action: extra.action
            ))
        }
        menu.addItem(.separator())
    }
    static func addPlaylistRemovalItem(
        to menu: NSMenu,
        song: SubsonicSong,
        playlist: PlaylistSummary?,
        playlistIndex: Int?,
        app: AppState
    ) {
        let targetPlaylist: PlaylistSummary? = {
            if let playlist { return playlist }
            if song.id == app.player.currentSong?.id {
                return app.player.currentPlaylist
            }
            return nil
        }()
        guard let targetPlaylist,
              !(targetPlaylist.isReadonly ?? false),
              !targetPlaylist.isSmart else { return }

        menu.addItem(SongMenuActionItem(
            title: "Убрать из плейлиста".localized,
            systemImage: "trash"
        ) {
            guard app.confirmOfflineAction() else { return }
            Task {
                await app.removeSong(song, from: targetPlaylist, at: playlistIndex)
            }
        })
    }
    static func addPlaylistActions(
        to menu: NSMenu,
        song: SubsonicSong,
        targets: [SubsonicSong],
        playlistContext: (playlist: PlaylistSummary?, index: Int?),
        app: AppState
    ) {
        addPlaylistSubmenu(to: menu, targets: targets, app: app)
        addPlaylistRemovalItem(
            to: menu,
            song: song,
            playlist: playlistContext.playlist,
            playlistIndex: playlistContext.index,
            app: app
        )
    }
}

/// Constructs the canonical set of song actions as an `NSMenu` for synchronous display.
/// Evaluates state only when called on demand (e.g. upon clicking the ellipsis button).
@MainActor
func buildSongActionMenu(
    for song: SubsonicSong,
    app: AppState,
    selection: [SubsonicSong] = [],
    playlist: PlaylistSummary? = nil,
    playlistIndex: Int? = nil,
    onPlay: (() -> Void)? = nil,
    extraActions: [SongMenuExtraAction] = []
) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let targets = selection.isEmpty ? [song] : selection
    let primaryCached = targets.count > 1 ? targets.allSatisfy { app.isCached($0) } : app.isCached(song)
    let isPlayableOffline = !app.isOfflineSession || primaryCached

    SongActionMenuBuilder.addExtraActions(to: menu, extraActions: extraActions)

    SongActionMenuBuilder.addPlaybackItems(
        to: menu,
        targets: targets,
        app: app,
        isPlayableOffline: isPlayableOffline,
        onPlay: onPlay
    )

    menu.addItem(.separator())

    SongActionMenuBuilder.addPlaylistActions(
        to: menu,
        song: song,
        targets: targets,
        playlistContext: (playlist, playlistIndex),
        app: app
    )

    SongActionMenuBuilder.addFavoriteAndDownloadItems(
        to: menu,
        song: song,
        targets: targets,
        app: app
    )

    SongActionMenuBuilder.addRatingSubmenu(
        to: menu,
        song: song,
        targets: targets,
        app: app
    )

    menu.addItem(.separator())

    SongActionMenuBuilder.addNavigationItems(
        to: menu,
        song: song,
        app: app
    )

    menu.addItem(.separator())

    SongActionMenuBuilder.addMetadataItems(
        to: menu,
        song: song,
        app: app
    )

    return menu
}

/// Shows the canonical song context menu on demand at the current mouse position.
@MainActor
func showSongActionMenu(
    for song: SubsonicSong,
    app: AppState,
    selection: [SubsonicSong] = [],
    playlist: PlaylistSummary? = nil,
    playlistIndex: Int? = nil,
    onPlay: (() -> Void)? = nil,
    extraActions: [SongMenuExtraAction] = []
) {
    let menu = buildSongActionMenu(
        for: song,
        app: app,
        selection: selection,
        playlist: playlist,
        playlistIndex: playlistIndex,
        onPlay: onPlay,
        extraActions: extraActions
    )
    guard let window = NSApp.currentEvent?.window ?? NSApp.keyWindow ?? NSApp.mainWindow,
          let view = window.contentView else {
        return
    }
    let mouseLocation = NSEvent.mouseLocation
    let locationInWindow = window.convertPoint(fromScreen: mouseLocation)
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: locationInWindow,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    ) ?? NSApp.currentEvent
    guard let event else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: view)
}
