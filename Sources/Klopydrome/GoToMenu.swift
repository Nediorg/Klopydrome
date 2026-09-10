import AppKit
import NavidromeClient

// MARK: - Shared “Go to” menu for a song (artist / album / playlist)

/// Shows a small `NSMenu` at the current mouse location. Used for the
/// left-click on a song's title/subtitle in `SongRow`, `MiniPlayerView` and
/// `PlayerLCDView`. The menu is built on the main actor and popped
/// synchronously, so the helper that owns the targets stays alive for the
/// duration of the modal `popUpContextMenu` call.
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
    if let artistId = song.artistId, !(song.artist?.isEmpty ?? true) {
        let item = NSMenuItem(
            title: "Перейти к исполнителю",
            action: #selector(GoToMenuHelper.goToArtist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(
            systemSymbolName: "music.mic",
            accessibilityDescription: nil
        )
        menu.addItem(item)
    }
    if let albumId = song.albumId {
        let item = NSMenuItem(
            title: "Перейти к альбому",
            action: #selector(GoToMenuHelper.goToAlbum),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(
            systemSymbolName: "square.stack",
            accessibilityDescription: nil
        )
        menu.addItem(item)
    }
    let containing = helper.appState.playlistsContaining(song)
    if containing.isEmpty {
        // No known playlist contains this song — omit the item instead of
        // a useless "Все плейлисты" jump. If user is inside a playlist,
        // that playlist will be in `containing` (already loaded), so it
        // still appears.
    } else if containing.count == 1, let playlist = containing.first {
        helper.singlePlaylist = playlist
        let item = NSMenuItem(
            title: "Перейти к плейлисту",
            action: #selector(GoToMenuHelper.goToSinglePlaylist),
            keyEquivalent: ""
        )
        item.target = helper
        item.image = NSImage(
            systemSymbolName: "music.note.list",
            accessibilityDescription: nil
        )
        menu.addItem(item)
    } else {
        let parent = NSMenuItem(
            title: "Перейти к плейлисту",
            action: nil,
            keyEquivalent: ""
        )
        parent.image = NSImage(
            systemSymbolName: "music.note.list",
            accessibilityDescription: nil
        )
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
    return menu
}

@MainActor
private final class GoToMenuHelper: NSObject {
    let appState: AppState
    let track: SubsonicSong
    var singlePlaylist: PlaylistSummary?

    init(app: AppState, song: SubsonicSong) {
        self.appState = app
        self.track = song
    }

    @objc func goToArtist() {
        guard let identifier = track.artistId else { return }
        let artist = Artist.nowPlayingSummary(from: track, artistID: identifier)
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

    @objc func goToPlaylistFromSubmenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let playlist = appState.library.playlists.first(where: { $0.id == id }) else { return }
        appState.openPlaylist(playlist)
    }
}
