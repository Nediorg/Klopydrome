import Foundation
import NavidromeClient

// MARK: - Stale-While-Revalidate Disk Persistence & Background Warmup

extension AppState {
    private static let playlistsMetadataKey = "library_tab_playlists"
    private static let recentAlbumsMetadataKey = "library_tab_recent_albums"
    private static let albumsMetadataKey = "library_tab_albums"
    private static let artistsMetadataKey = "library_tab_artists"
    private static let genresMetadataKey = "library_tab_genres"
    private static let songsMetadataKey = "library_tab_songs"
    private static let homeShelvesMetadataKey = "library_tab_home_shelves"
    private static let favoritesArtistsMetadataKey = "library_tab_favorites_artists"
    private static let favoritesAlbumsMetadataKey = "library_tab_favorites_albums"
    private static let favoritesSongsMetadataKey = "library_tab_favorites_songs"

    /// Immediately restores cached tab manifests from the SSD (.metadata store)
    /// into memory at launch so visiting tabs feels instantaneous without network delay.
    func restoreLibraryFromDiskCache() async {
        guard let cache else { return }
        await restorePlaylistsAndAlbums(cache: cache)
        await restoreCatalogAndSongs(cache: cache)
        await restoreHomeAndFavorites(cache: cache)
    }

    private func restorePlaylistsAndAlbums(cache: CacheManager) async {
        // 1. Playlists
        if library.playlists.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.playlistsMetadataKey),
           let playlists = try? JSONDecoder().decode([PlaylistSummary].self, from: data),
           !playlists.isEmpty {
            library.playlists = playlists
            library.playlistsLoaded = true
        }

        // 2. Recently Added Albums
        if library.recentAlbums.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.recentAlbumsMetadataKey),
           let recent = try? JSONDecoder().decode([SubsonicAlbum].self, from: data),
           !recent.isEmpty {
            library.recentAlbums = recent
            library.recentAlbumsLoaded = true
        }

        // 3. Alphabetical Albums
        if library.albums.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.albumsMetadataKey),
           let albums = try? JSONDecoder().decode([SubsonicAlbum].self, from: data),
           !albums.isEmpty {
            library.albums = albums
            library.albumsLoaded = true
        }
    }

    private func restoreCatalogAndSongs(cache: CacheManager) async {
        // 4. Artists Index
        if library.artistIndexes.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.artistsMetadataKey),
           let indexes = try? JSONDecoder().decode([ArtistIndex].self, from: data),
           !indexes.isEmpty {
            library.artistIndexes = indexes
            library.artistIndexesLoaded = true
        }

        // 5. Genres
        if availableGenres.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.genresMetadataKey),
           let genres = try? JSONDecoder().decode([Genre].self, from: data),
           !genres.isEmpty {
            availableGenres = genres
        }

        // 6. Songs
        if library.songs.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.songsMetadataKey),
           let songs = try? JSONDecoder().decode([SubsonicSong].self, from: data),
           !songs.isEmpty {
            library.songs = songs
            library.songsLoaded = true
        }
    }

    private func restoreHomeAndFavorites(cache: CacheManager) async {
        // 7. Home Shelves
        if library.homeShelves.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.homeShelvesMetadataKey),
           let rawShelves = try? JSONDecoder().decode([String: [SubsonicAlbum]].self, from: data),
           !rawShelves.isEmpty {
            var shelves: [AlbumListType: [SubsonicAlbum]] = [:]
            for (rawType, albums) in rawShelves {
                if let type = AlbumListType(rawValue: rawType) {
                    shelves[type] = albums
                }
            }
            if !shelves.isEmpty {
                library.homeShelves = shelves
            }
        }

        // 8. Favorite Artists
        if library.favoritesArtists.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.favoritesArtistsMetadataKey),
           let artists = try? JSONDecoder().decode([Artist].self, from: data),
           !artists.isEmpty {
            library.favoritesArtists = artists
        }

        // 9. Favorite Albums
        if library.favoritesAlbums.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.favoritesAlbumsMetadataKey),
           let albums = try? JSONDecoder().decode([SubsonicAlbum].self, from: data),
           !albums.isEmpty {
            library.favoritesAlbums = albums
        }

        // 10. Favorite Songs
        if library.favoritesSongs.isEmpty,
           let data = await cache.readData(for: .metadata, key: Self.favoritesSongsMetadataKey),
           let songs = try? JSONDecoder().decode([SubsonicSong].self, from: data),
           !songs.isEmpty {
            library.favoritesSongs = songs
        }
    }

    /// Persists the latest playlists manifest to disk for instant next-launch recovery.
    func persistPlaylistsToDisk() async {
        guard let cache, !library.playlists.isEmpty else { return }
        if let data = try? JSONEncoder().encode(library.playlists) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.playlistsMetadataKey)
        }
    }

    /// Persists the latest recently added albums to disk for instant next-launch recovery.
    func persistRecentAlbumsToDisk() async {
        guard let cache, !library.recentAlbums.isEmpty else { return }
        if let data = try? JSONEncoder().encode(library.recentAlbums) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.recentAlbumsMetadataKey)
        }
    }

    /// Persists the first page of alphabetical albums to disk for instant next-launch recovery.
    func persistAlbumsToDisk() async {
        guard let cache, !library.albums.isEmpty else { return }
        if let data = try? JSONEncoder().encode(library.albums) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.albumsMetadataKey)
        }
    }

    /// Persists the latest artist index to disk for instant next-launch recovery.
    func persistArtistsToDisk() async {
        guard let cache, !library.artistIndexes.isEmpty else { return }
        if let data = try? JSONEncoder().encode(library.artistIndexes) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.artistsMetadataKey)
        }
    }

    /// Persists the latest genre list to disk for instant next-launch recovery.
    func persistGenresToDisk() async {
        guard let cache, !availableGenres.isEmpty else { return }
        if let data = try? JSONEncoder().encode(availableGenres) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.genresMetadataKey)
        }
    }

    /// Persists the cached songs list to disk for instant next-launch recovery.
    func persistSongsToDisk() async {
        guard let cache, !library.songs.isEmpty else { return }
        if let data = try? JSONEncoder().encode(library.songs) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.songsMetadataKey)
        }
    }

    /// Persists the latest home shelves to disk for instant next-launch recovery.
    func persistHomeShelvesToDisk() async {
        guard let cache, !library.homeShelves.isEmpty else { return }
        var rawShelves: [String: [SubsonicAlbum]] = [:]
        for (type, albums) in library.homeShelves {
            rawShelves[type.rawValue] = albums
        }
        if let data = try? JSONEncoder().encode(rawShelves) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.homeShelvesMetadataKey)
        }
    }

    /// Persists cached favorite artists, albums, and songs to disk for instant next-launch recovery.
    func persistFavoritesToDisk() async {
        guard let cache else { return }
        if !library.favoritesArtists.isEmpty,
           let data = try? JSONEncoder().encode(library.favoritesArtists) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.favoritesArtistsMetadataKey)
        }
        if !library.favoritesAlbums.isEmpty,
           let data = try? JSONEncoder().encode(library.favoritesAlbums) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.favoritesAlbumsMetadataKey)
        }
        if !library.favoritesSongs.isEmpty,
           let data = try? JSONEncoder().encode(library.favoritesSongs) {
            _ = try? await cache.write(data: data, to: .metadata, key: Self.favoritesSongsMetadataKey)
        }
    }

    /// Background prefetch run after successful server connection:
    /// hydrates disk cache immediately, then refreshes fresh data silently.
    func warmupLibrary() async {
        guard client != nil, !isOfflineSession else { return }

        // 1. Instant SSD hydration (0 ms perceived latency)
        await restoreLibraryFromDiskCache()

        // 2. Silent background playlist refresh
        await refreshPlaylists()

        // 3. Silent background recent albums prefetch
        await warmupRecentAlbums()

        // 4. Silent background alphabetical albums prefetch
        await warmupAlbums()

        // 5. Silent background artist index prefetch
        await warmupArtists()

        // 6. Silent background genres prefetch
        await warmupGenres()

        // 7. Background sync of starred items for offline cache if enabled
        await syncStarredForOfflineCacheIfNeeded()
    }

    private func warmupRecentAlbums() async {
        guard let client, !isOfflineSession else { return }
        if let fresh = try? await client.getAlbumList2(type: .newest, size: 48, offset: 0), !fresh.isEmpty {
            library.recentAlbums = fresh
            library.recentAlbumsLoaded = true
            library.recentAllLoaded = fresh.count < 48
            await persistRecentAlbumsToDisk()
        }
    }

    private func warmupAlbums() async {
        guard let client, !isOfflineSession else { return }
        if let fresh = try? await client.getAlbumList2(type: .alphabeticalByName, size: 48, offset: 0), !fresh.isEmpty {
            library.albums = fresh
            library.albumsLoaded = true
            library.albumsAllLoaded = fresh.count < 48
            await persistAlbumsToDisk()
        }
    }

    private func warmupArtists() async {
        guard let client, !isOfflineSession else { return }
        if let fresh = try? await client.getArtists(), !fresh.isEmpty {
            library.artistIndexes = fresh
            library.artistIndexesLoaded = true
            await persistArtistsToDisk()
        }
    }

    private func warmupGenres() async {
        guard let client, !isOfflineSession else { return }
        if let fresh = try? await client.getGenres(), !fresh.isEmpty {
            availableGenres = fresh
            await persistGenresToDisk()
        }
    }
}
