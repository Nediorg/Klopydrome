import Foundation
import NavidromeClient

extension AppState {
    func isPlaylistDownloading(_ playlistID: String) -> Bool {
        activeDownloadTasks.contains { task in
            if case .playlist(let playlist) = task.kind {
                return playlist.id == playlistID
            }
            return false
        }
    }

    func cancelPlaylistDownload(_ playlistID: String) {
        let matching = activeDownloadTasks.filter { task in
            if case .playlist(let playlist) = task.kind {
                return playlist.id == playlistID
            }
            return false
        }
        for task in matching {
            cancelDownloadTask(task)
        }
    }

    func isAlbumDownloading(_ albumID: String) -> Bool {
        activeDownloadTasks.contains { task in
            if case .album(let album) = task.kind {
                return album.id == albumID
            }
            return false
        }
    }

    func cancelAlbumDownload(_ albumID: String) {
        let matching = activeDownloadTasks.filter { task in
            if case .album(let album) = task.kind {
                return album.id == albumID
            }
            return false
        }
        for task in matching {
            cancelDownloadTask(task)
        }
    }

    func cancelSongDownload(_ song: SubsonicSong) {
        cancelDownload(song)
        downloadProgress.removeValue(forKey: song.id)
        for task in activeDownloadTasks {
            cancelDownloadSongInTask(taskID: task.id, song: song)
        }
        unregisterDownload(from: [song])
    }

    func cacheArtist(_ artist: Artist) {
        guard let client else { return }
        Task {
            guard let detail = try? await client.getArtist(id: artist.id),
                  let albums = detail.album, !albums.isEmpty else { return }
            for album in albums {
                await MainActor.run {
                    self.cacheAlbum(album)
                }
            }
        }
    }

    func cacheAllStarredSongs() {
        guard let client else { return }
        Task {
            guard let result = try? await client.getStarred2() else { return }
            await MainActor.run {
                self.library.favoritesSongs = result.songs
                self.library.favoritesLoaded = true
                guard !result.songs.isEmpty else { return }
                self.cacheSongs(result.songs, title: "Favorite tracks".localized)
            }
        }
    }

    func cacheAllStarredAlbums() {
        guard let client else { return }
        Task {
            guard let result = try? await client.getStarred2() else { return }
            await MainActor.run {
                self.library.favoritesAlbums = result.albums
                self.library.favoritesLoaded = true
                for album in result.albums {
                    self.cacheAlbum(album)
                }
            }
        }
    }

    func cacheAllStarredArtists() {
        guard let client else { return }
        Task {
            guard let result = try? await client.getStarred2() else { return }
            await MainActor.run {
                self.library.favoritesArtists = result.artists
                self.library.favoritesLoaded = true
                for artist in result.artists {
                    self.cacheArtist(artist)
                }
            }
        }
    }

    func autoCacheStarredItemIfNeeded<T: Starable>(_ item: T) {
        guard serverConfig.cacheEnabled else { return }
        if serverConfig.effectiveCacheStarredSongs, let song = item as? SubsonicSong {
            cacheSong(song)
        } else if serverConfig.effectiveCacheStarredAlbums, let album = item as? SubsonicAlbum {
            cacheAlbum(album)
        } else if serverConfig.effectiveCacheStarredArtists, let artist = item as? Artist {
            cacheArtist(artist)
        }
    }

    func syncStarredForOfflineCacheIfNeeded() async {
        let hasFavoritesCaching = serverConfig.effectiveCacheStarredSongs ||
            serverConfig.effectiveCacheStarredAlbums ||
            serverConfig.effectiveCacheStarredArtists
        guard serverConfig.cacheEnabled,
              hasFavoritesCaching,
              let client, !isOfflineSession else { return }

        guard let result = try? await client.getStarred2() else { return }
        library.favoritesArtists = result.artists
        library.favoritesAlbums = result.albums
        library.favoritesSongs = result.songs
        library.favoritesLoaded = true

        if serverConfig.effectiveCacheStarredSongs, !result.songs.isEmpty {
            cacheSongs(result.songs, title: "Favorite tracks".localized)
        }
        if serverConfig.effectiveCacheStarredAlbums, !result.albums.isEmpty {
            for album in result.albums {
                cacheAlbum(album)
            }
        }
        if serverConfig.effectiveCacheStarredArtists, !result.artists.isEmpty {
            for artist in result.artists {
                cacheArtist(artist)
            }
        }
    }
}
