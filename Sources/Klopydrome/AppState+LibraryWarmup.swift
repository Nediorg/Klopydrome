import Foundation
import NavidromeClient

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

    func restoreLibraryFromDiskCache() async {
        guard let cache else { return }
        await restorePlaylistsAndAlbums(cache: cache)
        await restoreCatalogAndSongs(cache: cache)
        await restoreHomeAndFavorites(cache: cache)
    }

    private func readCached<T: Decodable>(cache: CacheManager, key: String) async -> T? {
        guard let data = await cache.readData(for: .metadata, key: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func readCachedArray<T: Decodable>(cache: CacheManager, key: String) async -> [T]? {
        guard let data = await cache.readData(for: .metadata, key: key),
              let items = try? JSONDecoder().decode([T].self, from: data),
              !items.isEmpty else { return nil }
        return items
    }

    private func writeCached<T: Encodable>(cache: CacheManager, key: String, value: T) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        _ = try? await cache.write(data: data, to: .metadata, key: key)
    }

    private func restorePlaylistsAndAlbums(cache: CacheManager) async {
        if library.playlists.isEmpty,
           let items: [PlaylistSummary] = await readCachedArray(cache: cache, key: Self.playlistsMetadataKey) {
            library.playlists = items
            library.playlistsLoaded = true
        }
        if library.recentAlbums.isEmpty,
           let items: [SubsonicAlbum] = await readCachedArray(cache: cache, key: Self.recentAlbumsMetadataKey) {
            library.recentAlbums = items
            library.recentAlbumsLoaded = true
        }
        if library.albums.isEmpty,
           let items: [SubsonicAlbum] = await readCachedArray(cache: cache, key: Self.albumsMetadataKey) {
            library.albums = items
            library.albumsLoaded = true
        }
    }

    private func restoreCatalogAndSongs(cache: CacheManager) async {
        if library.artistIndexes.isEmpty,
           let items: [ArtistIndex] = await readCachedArray(cache: cache, key: Self.artistsMetadataKey) {
            library.artistIndexes = items
            library.artistIndexesLoaded = true
        }
        if availableGenres.isEmpty,
           let items: [Genre] = await readCachedArray(cache: cache, key: Self.genresMetadataKey) {
            availableGenres = items
        }
    }

    func restoreCachedSongsIfNeeded() async {
        guard library.songs.isEmpty, let cache else { return }
        if let items: [SubsonicSong] = await readCachedArray(cache: cache, key: Self.songsMetadataKey) {
            library.songs = items.uniqued()
            library.songsLoaded = true
        }
    }

    private func restoreHomeAndFavorites(cache: CacheManager) async {
        if library.homeShelves.isEmpty,
           let raw: [String: [SubsonicAlbum]] = await readCached(cache: cache, key: Self.homeShelvesMetadataKey),
           !raw.isEmpty {
            let mapped = raw.compactMap { rawType, albums in
                AlbumListType(rawValue: rawType).map { ($0, albums) }
            }
            if !mapped.isEmpty {
                library.homeShelves = Dictionary(uniqueKeysWithValues: mapped)
            }
        }

        if library.favoritesArtists.isEmpty,
           let items: [Artist] = await readCachedArray(cache: cache, key: Self.favoritesArtistsMetadataKey) {
            library.favoritesArtists = items
        }
        if library.favoritesAlbums.isEmpty,
           let items: [SubsonicAlbum] = await readCachedArray(cache: cache, key: Self.favoritesAlbumsMetadataKey) {
            library.favoritesAlbums = items
        }
        if library.favoritesSongs.isEmpty,
           let items: [SubsonicSong] = await readCachedArray(cache: cache, key: Self.favoritesSongsMetadataKey) {
            library.favoritesSongs = items
        }
    }

    func persistPlaylistsToDisk() async {
        guard let cache, !library.playlists.isEmpty else { return }
        await writeCached(cache: cache, key: Self.playlistsMetadataKey, value: library.playlists)
    }

    func persistRecentAlbumsToDisk() async {
        guard let cache, !library.recentAlbums.isEmpty else { return }
        await writeCached(cache: cache, key: Self.recentAlbumsMetadataKey, value: library.recentAlbums)
    }

    func persistAlbumsToDisk() async {
        guard let cache, !library.albums.isEmpty else { return }
        await writeCached(cache: cache, key: Self.albumsMetadataKey, value: library.albums)
    }

    func persistArtistsToDisk() async {
        guard let cache, !library.artistIndexes.isEmpty else { return }
        await writeCached(cache: cache, key: Self.artistsMetadataKey, value: library.artistIndexes)
    }

    func persistGenresToDisk() async {
        guard let cache, !availableGenres.isEmpty else { return }
        await writeCached(cache: cache, key: Self.genresMetadataKey, value: availableGenres)
    }

    func persistSongsToDisk() async {
        guard let cache, !library.songs.isEmpty else { return }
        let unique = library.songs.uniqued()
        await writeCached(cache: cache, key: Self.songsMetadataKey, value: unique)
    }

    func persistHomeShelvesToDisk() async {
        guard let cache, !library.homeShelves.isEmpty else { return }
        let raw = Dictionary(uniqueKeysWithValues: library.homeShelves.map { ($0.key.rawValue, $0.value) })
        await writeCached(cache: cache, key: Self.homeShelvesMetadataKey, value: raw)
    }

    func persistFavoritesToDisk() async {
        guard let cache else { return }
        if !library.favoritesArtists.isEmpty {
            await writeCached(cache: cache, key: Self.favoritesArtistsMetadataKey, value: library.favoritesArtists)
        }
        if !library.favoritesAlbums.isEmpty {
            await writeCached(cache: cache, key: Self.favoritesAlbumsMetadataKey, value: library.favoritesAlbums)
        }
        if !library.favoritesSongs.isEmpty {
            await writeCached(cache: cache, key: Self.favoritesSongsMetadataKey, value: library.favoritesSongs)
        }
    }

    func warmupLibrary() async {
        guard client != nil, !isOfflineSession else { return }

        await restoreLibraryFromDiskCache()

        let isConstrained = NetworkMonitor.shared.isConstrained || NetworkMonitor.shared.isExpensive

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshPlaylists() }
            group.addTask { await self.warmupRecentAlbums() }

            if !isConstrained {
                group.addTask { await self.warmupAlbums() }
                group.addTask { await self.warmupArtists() }
                group.addTask { await self.warmupGenres() }
                group.addTask { await self.syncStarredForOfflineCacheIfNeeded() }
            }
        }
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
