import Foundation
import NavidromeClient

extension AppState {
    func passwordForLoginPrefill() -> String? {
        if didReadKeychainPassword { return cachedKeychainPassword }
        didReadKeychainPassword = true
        cachedKeychainPassword = KeychainStore.password(account: serverConfig.username)
        return cachedKeychainPassword
    }

    func beginAutomaticPlaybackCache(for song: SubsonicSong) -> URL? {
        cancelAutomaticPlaybackCache()
        guard serverConfig.cacheEnabled, usesMPVEngine, !isCached(song),
              let cache else { return nil }

        let directory = cache.directory(for: .streams)
            .deletingLastPathComponent()
            .appendingPathComponent("recording", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(effectiveSuffix(for: song))
        automaticPlaybackRecording = (song, temporaryURL)
        return temporaryURL
    }

    func cancelAutomaticPlaybackCache() {
        player.cancelStreamRecord()
        automaticPlaybackRecording = nil
    }

    func finishAutomaticPlaybackCache(at temporaryURL: URL) async {
        guard let recording = automaticPlaybackRecording,
              recording.temporaryURL == temporaryURL,
              let cache,
              (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0 > 0 else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return
        }

        automaticPlaybackRecording = nil
        let key = CacheManager.streamKey(
            songId: recording.song.id,
            suffix: effectiveSuffix(for: recording.song)
        )
        do {
            try await cache.moveFile(from: temporaryURL, to: .streams, key: key)
            cachedStreamKeys.insert(cache.fileURL(for: .streams, key: key).lastPathComponent)
            await persistOfflineSong(recording.song)
            prependDownloaded(recording.song)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    /// Restores the in-memory offline download list from the on-disk catalog.
    /// Runs on EVERY connection (online and offline) so the Downloads popover
    /// and the offline bookkeeping reflect what is actually on disk. It must
    /// NOT touch `library`: after an online `connect()` the library was just
    /// reset to a fresh `LibraryCache()`, and stamping it with the offline
    /// subset here is what made the Home shelves stay empty and every tab show
    /// only downloaded songs, never re-fetching from the server.
    func restoreOfflineCatalog() async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        let songs = store.load().filter { cachedURL(for: $0) != nil }
        replaceDownloadedSongs(songs)
        store.save(songs)
    }

    /// Stamps the library cache with the persisted offline snapshot. Only used
    /// inside `beginOfflineSession()`: an offline session has no server, so the
    /// tabs must render the saved songs/albums/playlists and mark every store
    /// as loaded (otherwise each tab would show its spinner forever).
    func restoreOfflineLibrary() async {
        await restoreOfflineCatalog()
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        let songs = downloadedSongs
        let snapshot = store.loadSnapshot()
        let albums = offlineAlbums(from: songs, snapshot: snapshot)
        let playlists = snapshot.playlists.filter { summary in
            guard let entries = snapshot.playlistDetails[summary.id]?.entry else { return false }
            return entries.contains { song in songs.contains(where: { $0.id == song.id }) }
        }

        library.songs = songs
        library.songsLoaded = true
        library.albums = albums
        library.albumsLoaded = true
        library.albumsAllLoaded = true
        library.recentAlbums = albums
        library.recentAlbumsLoaded = true
        library.recentAllLoaded = true
        library.favoritesSongs = songs
        library.favoritesLoaded = true
        library.playlists = playlists
        library.playlistsLoaded = true
        library.homeShelves = [:]
        library.homeShelvesLoaded = true
    }

    func persistOfflineSong(_ song: SubsonicSong) async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        var songs = store.load()
        songs.removeAll { $0.id == song.id }
        songs.insert(song, at: 0)
        store.save(songs)
    }

    func removeOfflineSong(_ song: SubsonicSong) async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        store.save(store.load().filter { $0.id != song.id })
    }

    func clearOfflineCatalog() async {
        guard let cache else { return }
        await OfflineLibraryStore(cache: cache).clear()
    }

    func persistOfflinePlaylists(_ playlists: [PlaylistSummary]) async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        var snapshot = store.loadSnapshot()
        snapshot.playlists = playlists
        store.saveSnapshot(snapshot)
    }

    func persistOfflineAlbumDetail(_ detail: AlbumDetail) async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        var snapshot = store.loadSnapshot()
        snapshot.albumDetails[detail.id] = detail
        let summary = SubsonicAlbum(
            id: detail.id,
            title: detail.name,
            album: detail.name,
            name: detail.name,
            artist: detail.artist,
            artistId: detail.artistId,
            coverArt: detail.coverArt,
            songCount: detail.songCount,
            duration: detail.duration,
            created: detail.created,
            year: detail.year,
            genre: detail.genre,
            starred: detail.starred
        )
        snapshot.albums.removeAll { $0.id == summary.id }
        snapshot.albums.insert(summary, at: 0)
        store.saveSnapshot(snapshot)
    }

    func persistOfflinePlaylistDetail(_ detail: PlaylistDetail) async {
        guard let cache else { return }
        let store = OfflineLibraryStore(cache: cache)
        var snapshot = store.loadSnapshot()
        snapshot.playlistDetails[detail.id] = detail
        let summary = PlaylistSummary(
            id: detail.id,
            name: detail.name,
            comment: detail.comment,
            owner: detail.owner,
            coverArt: detail.coverArt,
            songCount: detail.songCount,
            duration: detail.duration,
            created: detail.created,
            changed: detail.changed,
            isPublic: detail.isPublic,
            isReadonly: detail.isReadonly,
            validUntil: detail.validUntil
        )
        snapshot.playlists.removeAll { $0.id == summary.id }
        snapshot.playlists.insert(summary, at: 0)
        store.saveSnapshot(snapshot)
    }

    func offlineAlbumDetail(for albumID: String) -> AlbumDetail? {
        guard let cache else { return nil }
        let snapshot = OfflineLibraryStore(cache: cache).loadSnapshot()
        let songs = offlineSongs(in: snapshot.albumDetails[albumID]?.song ?? downloadedSongs)
            .filter { ($0.albumId ?? $0.parent) == albumID }
        guard !songs.isEmpty else { return nil }

        if let saved = snapshot.albumDetails[albumID] {
            return AlbumDetail(
                id: saved.id,
                name: saved.name,
                artist: saved.artist,
                artistId: saved.artistId,
                coverArt: saved.coverArt,
                songCount: songs.count,
                duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
                playCount: saved.playCount,
                created: saved.created,
                year: saved.year,
                genre: saved.genre,
                recordType: saved.recordType,
                musicBrainzId: saved.musicBrainzId,
                starred: saved.starred,
                starId: saved.starId,
                song: songs
            )
        }

        let song = songs[0]
        return AlbumDetail(
            id: albumID,
            name: song.album,
            artist: song.albumArtist ?? song.artist,
            artistId: song.artistId,
            coverArt: song.coverArt,
            songCount: songs.count,
            duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
            year: song.year,
            genre: song.genre,
            song: songs
        )
    }

    func offlinePlaylistDetail(for playlistID: String) -> PlaylistDetail? {
        guard let cache else { return nil }
        guard let saved = OfflineLibraryStore(cache: cache).loadSnapshot().playlistDetails[playlistID] else {
            return nil
        }
        let songs = offlineSongs(in: saved.entry ?? [])
        guard !songs.isEmpty else { return nil }
        return PlaylistDetail(
            id: saved.id,
            name: saved.name,
            comment: saved.comment,
            owner: saved.owner,
            coverArt: saved.coverArt,
            songCount: songs.count,
            duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
            created: saved.created,
            changed: saved.changed,
            isPublic: saved.isPublic,
            isReadonly: saved.isReadonly,
            validUntil: saved.validUntil,
            entry: songs
        )
    }

    func beginOfflineSession() async -> Bool {
        guard !serverConfig.url.isEmpty,
              let host = URL(string: serverConfig.url)?.host else {
            return false
        }

        let offlineCache = CacheManager(rootURL: CacheManager.root(forServer: host))
        cache = offlineCache
        resetCacheState()
        await applyCacheLimits()
        await seedCachedStreamKeys()
        // Viability gate BEFORE restoreOfflineLibrary stamps the in-memory
        // library with the snapshot: with no downloaded files the snapshot is
        // empty, and stamping it would drop every tab (playlists included) to
        // zero on a mere failed reconnect — while the last known server state
        // is still perfectly good to display. Bail out with it untouched.
        let probe = OfflineLibraryStore(cache: offlineCache)
        guard !probe.load().filter({ cachedURL(for: $0) != nil }).isEmpty else {
            cache = nil
            resetCacheState()
            return false
        }
        await restoreOfflineLibrary()

        nav.selected = .songs
        nav.selectedPlaylist = nil
        isOfflineSession = true
        return true
    }

    private func offlineAlbums(
        from songs: [SubsonicSong],
        snapshot: OfflineLibrarySnapshot
    ) -> [SubsonicAlbum] {
        let grouped = Dictionary(grouping: songs, by: { $0.albumId ?? $0.parent ?? $0.album ?? $0.id })
        let saved = Dictionary(uniqueKeysWithValues: snapshot.albums.map { ($0.id, $0) })
        return grouped.compactMap { id, tracks in
            guard let first = tracks.first else { return nil }
            if let album = saved[id] { return album }
            return SubsonicAlbum(
                id: id,
                title: first.album,
                album: first.album,
                name: first.album,
                artist: first.albumArtist ?? first.artist,
                artistId: first.artistId,
                coverArt: first.coverArt,
                songCount: tracks.count,
                duration: tracks.reduce(0) { $0 + ($1.duration ?? 0) },
                year: first.year,
                genre: first.genre
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func offlineSongs(in songs: [SubsonicSong]) -> [SubsonicSong] {
        songs.filter { cachedURL(for: $0) != nil }
    }
}
