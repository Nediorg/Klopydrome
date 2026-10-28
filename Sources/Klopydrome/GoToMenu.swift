import AppKit
import NavidromeClient

@MainActor
func showGoToMenu(for song: SubsonicSong, app: AppState) {
    let helper = GoToMenuHelper(app: app, song: song)
    let menu = buildGoToMenu(for: song, helper: helper)
    guard let event = NSApp.currentEvent,
          let view = event.window?.contentView ?? NSApp.keyWindow?.contentView else {
        let location = NSEvent.mouseLocation
        guard let window = NSApp.keyWindow,
              let view = window.contentView else { return }
        let fakeEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: window.convertPoint(fromScreen: location),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
        if let fakeEvent { NSMenu.popUpContextMenu(menu, with: fakeEvent, for: view) }
        return
    }
    NSMenu.popUpContextMenu(menu, with: event, for: view)
}

@MainActor
private func buildGoToMenu(
    for song: SubsonicSong,
    helper: GoToMenuHelper
) -> NSMenu {
    let menu = NSMenu()
    addArtistAlbumItems(to: menu, for: song, helper: helper)
    addPlaylistItems(to: menu, for: song, helper: helper)
    return menu
}

@MainActor
private func addArtistAlbumItems(to menu: NSMenu, for song: SubsonicSong, helper: GoToMenuHelper) {
    let collaborators = SongCollaborators.parse(from: song, library: helper.appState.library)
    if collaborators.count > 1 {
        let parentItem = NSMenuItem(
            title: "Go to Artist".localized,
            action: nil,
            keyEquivalent: ""
        )
        parentItem.image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: nil)
        let subMenu = NSMenu()
        for artist in collaborators {
            let subItem = NSMenuItem(
                title: artist.name,
                action: #selector(GoToMenuHelper.goToSpecificArtist(_:)),
                keyEquivalent: ""
            )
            subItem.target = helper
            subItem.representedObject = artist
            subMenu.addItem(subItem)
        }
        parentItem.submenu = subMenu
        menu.addItem(parentItem)
    } else if let singleArtist = collaborators.first {
        helper.singleArtist = singleArtist
        let item = NSMenuItem(
            title: "Go to Artist".localized,
            action: #selector(GoToMenuHelper.goToArtist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(systemSymbolName: "music.mic", accessibilityDescription: nil)
        menu.addItem(item)
    }
    if song.albumId != nil {
        let item = NSMenuItem(
            title: "Go to Album".localized,
            action: #selector(GoToMenuHelper.goToAlbum),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
        menu.addItem(item)
    }
}

@MainActor
private func addActivePlaybackPlaylistItem(to menu: NSMenu, helper: GoToMenuHelper) -> Bool {
    if let current = helper.appState.player.currentPlaylist {
        helper.singlePlaylist = current
        let item = NSMenuItem(
            title: "Go to Playlist".localized,
            action: #selector(GoToMenuHelper.goToSinglePlaylist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)
        menu.addItem(item)
        return true
    }
    if case .smartPlaylist(let smart) = helper.appState.player.playbackContext {
        helper.singleSmartPlaylist = smart
        let item = NSMenuItem(
            title: "Go to Playlist".localized,
            action: #selector(GoToMenuHelper.goToSmartPlaylist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(item)
        return true
    }
    return false
}

@MainActor
private func addPlaylistItems(to menu: NSMenu, for song: SubsonicSong, helper: GoToMenuHelper) {
    if addActivePlaybackPlaylistItem(to: menu, helper: helper) {
        return
    }

    let containing = helper.appState.playlistsContaining(song)
    if containing.count == 1, let playlist = containing.first {
        helper.singlePlaylist = playlist
        let item = NSMenuItem(
            title: "Go to Playlist".localized,
            action: #selector(GoToMenuHelper.goToSinglePlaylist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)
        menu.addItem(item)
    } else if containing.count > 1 {
        let parent = NSMenuItem(
            title: "Go to Playlist".localized,
            action: nil,
            keyEquivalent: ""
        )
        parent.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)
        let submenu = NSMenu()
        for playlist in containing {
            let item = NSMenuItem(
                title: playlist.displayName,
                action: #selector(GoToMenuHelper.goToPlaylistFromSubmenu(_:)),
                keyEquivalent: ""
            )
            item.target = helper
            item.representedObject = playlist.id
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }
}

@MainActor
private final class GoToMenuHelper: NSObject {
    let appState: AppState
    let track: SubsonicSong
    var singleArtist: Artist?
    var singlePlaylist: PlaylistSummary?
    var singleSmartPlaylist: SmartPlaylist?

    init(app: AppState, song: SubsonicSong) {
        self.appState = app
        self.track = song
    }

    @objc func goToArtist() {
        if let artist = singleArtist {
            appState.openArtistInLibrary(artist)
        } else if let identifier = track.artistId {
            let artist = Artist.nowPlayingSummary(from: track, artistID: identifier)
            appState.openArtistInLibrary(artist)
        }
    }

    @objc func goToSpecificArtist(_ sender: NSMenuItem) {
        guard let artist = sender.representedObject as? Artist else { return }
        appState.openArtistInLibrary(artist)
    }

    @objc func goToAlbum() {
        guard let identifier = track.albumId else { return }
        let album = SubsonicAlbum.nowPlayingSummary(from: track, albumID: identifier)
        appState.openAlbumInLibrary(album)
    }

    @objc func goToSinglePlaylist() {
        guard let playlist = singlePlaylist else { return }
        appState.openPlaylist(playlist)
    }

    @objc func goToSmartPlaylist() {
        guard let playlist = singleSmartPlaylist else { return }
        appState.openSmartPlaylist(playlist)
    }

    @objc func goToPlaylistFromSubmenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let playlist = appState.library.playlists.first(where: { $0.id == id }) else { return }
        appState.openPlaylist(playlist)
    }
}
