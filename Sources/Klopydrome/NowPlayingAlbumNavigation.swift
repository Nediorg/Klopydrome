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
        pushDestination(.album(album))
    }

    func openSongDetails(_ song: SubsonicSong) {
        pushDestination(.song(song))
    }

    func openArtistInLibrary(_ artist: Artist) {
        pushDestination(.artist(artist))
    }

    func openAlbumArtistInLibrary(_ song: SubsonicSong) {
        if let albumArtistId = song.albumArtistId {
            pushDestination(.artist(Artist(id: albumArtistId, name: song.effectiveAlbumArtist)))
        } else if let artistId = song.artistId, song.albumArtist == nil || song.albumArtist == song.artist {
            pushDestination(.artist(Artist(id: artistId, name: song.effectiveAlbumArtist)))
        } else {
            MiniPlayerPanelController.shared.closeForLibraryNavigation()
            nav.selectedPlaylist = nil
            nav.searchQuery = song.effectiveAlbumArtist
            nav.selected = .search
            nav.history.removeAll()
            nav.forwardHistory.removeAll()
            nav.navVersion += 1
        }
    }

    func openPlaylistsLibrary() {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.selectedPlaylist = nil
        nav.history.removeAll()
        nav.forwardHistory.removeAll()
        nav.selected = .playlists
        nav.navVersion += 1
    }

    func openPlaylist(_ playlist: PlaylistSummary) {
        recordRecentPlaylist(playlist.id)
        pushDestination(.playlist(playlist))
    }

    private func pushDestination(_ destination: NavigationState.Destination) {
        MiniPlayerPanelController.shared.closeForLibraryNavigation()
        nav.history.append(destination)
        nav.forwardHistory.removeAll()
        nav.navVersion += 1
    }

    func openSmartPlaylist(_ playlist: SmartPlaylist) {
        if let summary = library.playlists.first(where: { $0.id == playlist.id }) {
            openPlaylist(summary)
            return
        }
        let fallback = PlaylistSummary(id: playlist.id, name: playlist.name, validUntil: "smart")
        openPlaylist(fallback)
    }

    var canNavigateBack: Bool {
        !nav.history.isEmpty || nav.selectedPlaylist != nil
    }

    var canNavigateForward: Bool {
        !nav.forwardHistory.isEmpty
    }

    func navigateBack() {
        if let last = nav.history.popLast() {
            nav.forwardHistory.append(last)
        } else if nav.selectedPlaylist != nil {
            nav.selected = .playlists
            nav.selectedPlaylist = nil
        }
        nav.navVersion += 1
    }

    func navigateForward() {
        guard let next = nav.forwardHistory.popLast() else { return }
        nav.history.append(next)
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
