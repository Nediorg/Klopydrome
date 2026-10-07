import Foundation
import NavidromeClient

// MARK: - Stale-While-Revalidate Disk Persistence & Background Warmup

extension AppState {
    private static let playlistsMetadataKey = "library_tab_playlists"
    private static let recentAlbumsMetadataKey = "library_tab_recent_albums"
    private static let homeShelvesMetadataKey = "library_tab_home_shelves"

    /// Immediately restores cached tab manifests from the SSD (.metadata store)
    /// into memory at launch so visiting tabs feels instantaneous without network delay.
    func restoreLibraryFromDiskCache() async {
        guard let cache else { return }

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

        // 3. Home Shelves
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
                library.homeShelvesLoaded = true
            }
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
}
