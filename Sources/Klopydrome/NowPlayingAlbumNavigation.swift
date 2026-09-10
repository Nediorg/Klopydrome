import Dispatch
import NavidromeClient
extension SubsonicAlbum {
    /// Builds the best immediately renderable album summary from a now-playing
    /// song while the destination fetches its authoritative album detail.
    static func nowPlayingSummary(from song: SubsonicSong, albumID: String) -> Self {
        Self(
            id: albumID,
            title: song.album,
            album: song.album,
            name: song.album,
            artist: song.albumArtist ?? song.artist,
            artistId: song.artistId,
            coverArt: song.coverArt,
            year: song.year,
            genre: song.genre
        )
    }
}

extension Artist {
    static func nowPlayingSummary(from song: SubsonicSong, artistID: String) -> Self {
        Self(id: artistID, name: song.artist ?? song.albumArtist ?? "Unknown Artist")
    }
}

extension AppState {
    /// Presents main-window-owned UI (sheets are attached to `MainView`) from
    /// any now-playing surface. When the mini-player panel is up, it yields
    /// focus back to the main window first and presentation happens on the
    /// next run-loop tick, once that window is visible again.
    func presentInMainWindow(_ present: @escaping @MainActor () -> Void) {
        guard MiniPlayerPanelController.shared.isVisible else {
            present()
            return
        }
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        DispatchQueue.main.async {
            present()
        }
    }

    /// Reveals an album in the main library from any now-playing surface.
    /// The request belongs to the main navigation stack; a mini-player-local
    /// path has no destination and would otherwise silently discard the action.
    /// The panel is closed FIRST so the main window is visible and key before
    /// the navigation state it observes changes.
    func openAlbumInLibrary(_ album: SubsonicAlbum) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = nil
        nav.selected = .albums
        nav.pendingAlbum = album
    }

    /// Opens the song-detail page in the main library from a surface outside
    /// the main navigation stack (the mini-player panel has no stack of its
    /// own). `DetailView` consumes `nav.pendingSong` once the window is front.
    func openSongDetails(_ song: SubsonicSong) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.pendingSong = song
    }

    func openArtistInLibrary(_ artist: Artist) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = nil
        nav.selected = .artists
        nav.pendingArtist = artist
    }

    /// Shows the playlists view — used as the “go to playlist” fallback from a
    /// song row when no single playlist context exists.
    func openPlaylistsLibrary() {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = nil
        nav.selected = .playlists
        nav.navVersion += 1
    }

    /// Reveals a concrete playlist in the main library.
    func openPlaylist(_ playlist: PlaylistSummary) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = playlist
        nav.selected = .playlists
        nav.navVersion += 1
    }

    /// Playlists that are known to contain the song, based on already-loaded
    /// details and load states. No extra network — only what the library has
    /// already fetched in this session.
    func playlistsContaining(_ song: SubsonicSong) -> [PlaylistSummary] {
        var result: [PlaylistSummary] = []
        for playlist in library.playlists {
            if let detail = library.playlistDetails[playlist.id],
               detail.entry?.contains(where: { $0.id == song.id }) == true {
                result.append(playlist)
                continue
            }
            if let state = playlistLoadStates[playlist.id],
               state.songs.contains(where: { $0.id == song.id }) {
                result.append(playlist)
            }
        }
        return result
    }
}
