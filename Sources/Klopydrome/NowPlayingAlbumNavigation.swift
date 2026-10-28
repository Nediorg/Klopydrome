import Dispatch
import NavidromeClient
extension SubsonicAlbum {
    static func nowPlayingSummary(from song: SubsonicSong, albumID: String) -> Self {
        Self(
            id: albumID,
            title: song.album,
            album: song.album,
            name: song.album,
            artist: song.albumArtist ?? song.artist,
            artistId: song.albumArtistId ?? song.artistId,
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

    static func albumArtistSummary(from song: SubsonicSong, artistID: String) -> Self {
        Self(id: artistID, name: song.albumArtist ?? song.artist ?? "Unknown Artist")
    }
}

extension AppState {
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

    func openAlbumInLibrary(_ album: SubsonicAlbum) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.album(album))
        nav.navVersion += 1
    }

    func openSongDetails(_ song: SubsonicSong) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.song(song))
        nav.navVersion += 1
    }

    func openArtistInLibrary(_ artist: Artist) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.artist(artist))
        nav.navVersion += 1
    }

    func openAlbumArtistInLibrary(_ song: SubsonicSong) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        if let albumArtistId = song.albumArtistId {
            nav.history.append(.artist(Artist(id: albumArtistId, name: song.effectiveAlbumArtist)))
            nav.navVersion += 1
        } else if let artistId = song.artistId, song.albumArtist == nil || song.albumArtist == song.artist {
            nav.history.append(.artist(Artist(id: artistId, name: song.effectiveAlbumArtist)))
            nav.navVersion += 1
        } else {
            nav.selectedPlaylist = nil
            nav.searchQuery = song.effectiveAlbumArtist
            nav.selected = .search
            nav.history.removeAll()
            nav.navVersion += 1
        }
    }

    func openPlaylistsLibrary() {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = nil
        nav.history.removeAll()
        nav.selected = .playlists
        nav.navVersion += 1
    }

    func openPlaylist(_ playlist: PlaylistSummary) {
        recordRecentPlaylist(playlist.id)
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.playlist(playlist))
        nav.navVersion += 1
    }

    func openSmartPlaylist(_ playlist: SmartPlaylist) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(.smartPlaylist(playlist))
        nav.navVersion += 1
    }

    func navigateBack() {
        if !nav.history.isEmpty {
            nav.history.removeLast()
        } else if nav.selectedPlaylist != nil {
            nav.selected = .playlists
            nav.selectedPlaylist = nil
        }
        nav.navVersion += 1
    }

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
