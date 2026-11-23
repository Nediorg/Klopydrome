import Foundation
import NavidromeClient

extension AppState {
    func passwordForLoginPrefill(for profile: ServerProfile? = nil) -> String? {
        let target = profile ?? activeProfile
        if let target {
            if let pw = KeychainStore.password(account: target.keychainAccount), !pw.isEmpty {
                cachedKeychainPassword = pw
                didReadKeychainPassword = true
                return pw
            }
            if let pw = KeychainStore.password(account: target.username), !pw.isEmpty {
                cachedKeychainPassword = pw
                didReadKeychainPassword = true
                return pw
            }
        }
        if didReadKeychainPassword { return cachedKeychainPassword }
        didReadKeychainPassword = true
        if !serverConfig.username.isEmpty {
            cachedKeychainPassword = KeychainStore.password(account: serverConfig.username)
        }
        return cachedKeychainPassword
    }

    var stagingDirectory: URL? {
        guard let cache else { return nil }
        let dir = cache.directory(for: .streams)
            .deletingLastPathComponent()
            .appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func beginAutomaticPlaybackCache(for song: SubsonicSong, streamURL: URL? = nil) -> URL? {
        cancelAutomaticPlaybackCache()
        guard serverConfig.cacheEnabled, usesMPVEngine, !isCached(song),
              let cache else { return nil }
        if let streamURL,
           URLComponents(url: streamURL, resolvingAgainstBaseURL: false)?
               .queryItems?.contains(where: { $0.name == "timeOffset" }) == true {
            return nil
        }

        let directory = stagingDirectory ?? cache.directory(for: .streams)
            .deletingLastPathComponent()
            .appendingPathComponent("staging", isDirectory: true)
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

    private func consumeAutomaticPlaybackRecording(matching url: URL) -> (song: SubsonicSong, temporaryURL: URL)? {
        guard let recording = automaticPlaybackRecording,
              recording.temporaryURL == url else {
            return nil
        }
        automaticPlaybackRecording = nil
        return recording
    }

    func finishAutomaticPlaybackCache(_ completion: MPVPlaybackEngine.StreamRecordCompletion) async {
        let temporaryURL = completion.url
        guard let recording = consumeAutomaticPlaybackRecording(matching: temporaryURL),
              let cache,
              let fileSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return
        }
        let metaDuration = Double(recording.song.duration ?? 0)
        let expectedDuration = max(metaDuration, completion.streamDuration)
        if expectedDuration > 0 {
            let tolerance = player.silenceTrimMode == .off
                ? max(4.0, expectedDuration * 0.05)
                : max(12.0, expectedDuration * 0.15)
            guard completion.reachedTime + tolerance >= expectedDuration else {
                try? FileManager.default.removeItem(at: temporaryURL)
                return
            }
        }
        let minBytes = AppState.minimumExpectedCacheBytes(for: recording.song)
        guard fileSize >= minBytes, AudioFileValidator.isValidAudioFile(at: temporaryURL) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return
        }

        let key = CacheManager.streamKey(
            songId: recording.song.id,
            suffix: effectiveSuffix(for: recording.song)
        )
        let meta = AudioTagMetadata(song: recording.song, coverArtData: coverArtData(for: recording.song))
        try? await AudioMetadataWriter.inject(meta, into: temporaryURL)
        do {
            try await cache.moveFile(from: temporaryURL, to: .streams, key: key)
            cachedStreamKeys.insert(cache.fileURL(for: .streams, key: key).lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    func setupOfflineRepository(host: String) async {
        if offlineRepository != nil && currentOfflineHost == host {
            return
        }
        let repository: SwiftDataOfflineRepository?
        if let onDisk = try? SwiftDataOfflineRepository.makeDefault(serverHost: host) {
            repository = onDisk
        } else {
            repository = try? SwiftDataOfflineRepository.makeInMemory()
        }
        guard let repository else { return }
        self.offlineRepository = repository
        self.currentOfflineHost = host
        self.offlineMutationStore = OfflineMutationStore(serverHost: host)
        let cacheRoot = CacheManager.root(forServer: host)
        await OfflineMigration.migrateIfNeeded(cacheRoot: cacheRoot, repository: repository)
    }

    func restoreOfflineCatalog() async {
        guard let offlineRepository else { return }
        if !cachedStreamKeysSeeded {
            await seedCachedStreamKeys()
        }
        let tracks = (try? await offlineRepository.fetchDownloadedTracks()) ?? []
        let songs = tracks.filter { isCached($0) }
        replaceDownloadedSongs(songs)
        await syncProtectedCacheKeys()
    }

    func syncProtectedCacheKeys() async {
        guard let cache else { return }
        let keys = Set(downloadedSongs.flatMap { song in
            candidateSuffixes(for: song).map { CacheManager.streamKey(songId: song.id, suffix: $0) }
        })
        await cache.setProtectedKeys(keys)
    }

    var effectiveUsername: String {
        if let username = client?.config.username, !username.isEmpty {
            return username
        }
        return serverConfig.username
    }

    func restoreOfflineLibrary() async {
        await restoreOfflineCatalog()
        guard let offlineRepository else { return }
        let songs = downloadedSongs
        let downloadedAlbumIDs = Set(songs.compactMap { $0.albumId ?? $0.parent })
        let savedAlbums = (try? await offlineRepository.fetchAlbums()) ?? []
        let matchingSavedAlbums = savedAlbums.filter { downloadedAlbumIDs.contains($0.id) }
        let fallbackAlbums = offlineAlbums(from: songs)
        let matchingIDs = Set(matchingSavedAlbums.map(\.id))
        let missingAlbums = fallbackAlbums.filter { !matchingIDs.contains($0.id) }
        let albums = (matchingSavedAlbums + missingAlbums).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        let downloadedTrackIDs = Set(songs.map(\.id))
        let playlists = (try? await offlineRepository.fetchPlaylists(
            matchingDownloadedTrackIDs: downloadedTrackIDs
        )) ?? []

        library.songs = songs
        library.songsLoaded = true
        library.albums = albums
        library.albumsLoaded = true
        library.albumsAllLoaded = true
        library.recentAlbums = albums
        library.recentAlbumsLoaded = true
        library.recentAllLoaded = true
        library.favoritesSongs = songs.filter { $0.starred != nil || starOverrides[$0.id] == true }
        library.favoritesLoaded = true
        library.playlists = playlists
        library.playlistsLoaded = true
        library.artistIndexes = offlineArtistIndexes(from: songs)
        library.artistIndexesLoaded = true
        library.homeShelves = [:]
        library.homeShelvesLoaded = true
        await restorePendingOfflineMutations()
    }

    func persistOfflineSong(_ song: SubsonicSong) async {
        guard let offlineRepository else { return }
        try? await offlineRepository.saveTrack(song)
    }

    func removeOfflineSong(_ song: SubsonicSong) async {
        guard let offlineRepository else { return }
        try? await offlineRepository.removeTrack(id: song.id)
    }

    func clearOfflineCatalog() async {
        guard let offlineRepository else { return }
        try? await offlineRepository.clearAll()
    }

    func persistOfflinePlaylists(_ playlists: [PlaylistSummary]) async {
        guard let offlineRepository else { return }
        try? await offlineRepository.savePlaylists(playlists)
    }

    func persistOfflineAlbumDetail(_ detail: AlbumDetail) async {
        guard let offlineRepository else { return }
        try? await offlineRepository.saveAlbumDetail(detail)
    }

    func persistOfflinePlaylistDetail(_ detail: PlaylistDetail) async {
        guard let offlineRepository else { return }
        try? await offlineRepository.savePlaylistDetail(detail)
    }

    func offlineAlbumDetail(for albumID: String) async -> AlbumDetail? {
        if let offlineRepository,
           let detail = try? await offlineRepository.fetchAlbumDetail(id: albumID) {
            let hasAnyDownloaded = detail.song?.contains(where: { isCached($0) }) ?? false
            if hasAnyDownloaded {
                return detail
            }
        }

        let fallbackSongs = downloadedSongs.filter { ($0.albumId ?? $0.parent) == albumID }
        guard let first = fallbackSongs.first else { return nil }
        return AlbumDetail(
            id: albumID,
            name: first.album,
            artist: first.albumArtist ?? first.artist,
            artistId: first.artistId,
            coverArt: first.coverArt,
            songCount: fallbackSongs.count,
            duration: fallbackSongs.reduce(0) { $0 + ($1.duration ?? 0) },
            year: first.year,
            genre: first.genre,
            song: fallbackSongs
        )
    }

    func offlinePlaylistDetail(for playlistID: String) async -> PlaylistDetail? {
        guard let offlineRepository,
              let detail = try? await offlineRepository.fetchPlaylistDetail(id: playlistID) else {
            return nil
        }
        let hasAnyDownloaded = detail.entry?.contains(where: { isCached($0) }) ?? false
        guard hasAnyDownloaded else { return nil }
        return detail
    }

    func hydrateOfflineStoreIfNeeded(preserveExistingLibrary: Bool) async {
        guard !serverConfig.url.isEmpty else { return }
        let storageKey = effectiveStorageKey
        let offlineCache = cache ?? CacheManager(rootURL: CacheManager.root(forServer: storageKey))
        if cache == nil {
            cache = offlineCache
            resetCacheState()
        }
        if !cachedStreamKeysSeeded {
            await seedCachedStreamKeys()
        }
        await setupOfflineRepository(host: storageKey)
        if preserveExistingLibrary {
            await restoreOfflineCatalog()
            await restorePendingOfflineMutations()
        } else {
            await restoreLibraryFromDiskCache()
            let hasCachedHome = !library.homeShelves.isEmpty || !library.albums.isEmpty
            if hasCachedHome {
                await restoreOfflineCatalog()
                await restorePendingOfflineMutations()
            } else {
                await restoreOfflineLibrary()
            }
        }
        await applyCacheLimits()
    }

    func enterManualOfflineMode() async {
        guard !serverConfig.url.isEmpty else {
            updateConnectionState(.unconfigured)
            return
        }
        stopReconnectLoop()
        warmupTask?.cancel()
        warmupTask = nil
        stopScanStatusPolling()
        cancelPlaylistLoads()
        lyricsTask?.cancel()
        lyricsTask = nil
        pauseDownloadWorkerForOffline()

        client = nil
        navidrome = nil
        connectionError = nil
        updateConnectionState(.manualOffline)

        let storageKey = effectiveStorageKey
        let offlineCache = CacheManager(rootURL: CacheManager.root(forServer: storageKey))
        cache = offlineCache
        resetCacheState()
        await seedCachedStreamKeys()
        await setupOfflineRepository(host: storageKey)
        await restoreOfflineLibrary()
        await applyCacheLimits()
        CoverArtStore.shared.configure(
            client: nil,
            cache: offlineCache,
            coverResolution: serverConfig.coverResolution ?? .high,
            adaptiveCellularDataEnabled: serverConfig.effectiveAdaptiveCellularDataEnabled
        )
    }

    func offlineArtists(from songs: [SubsonicSong]) -> [Artist] {
        var artistsByID: [String: Artist] = [:]
        var albumIDsByArtist: [String: Set<String>] = [:]

        for song in songs {
            guard let artistName = extractSongArtistName(song) else { continue }
            let artistID = song.artistId ?? song.albumArtistId ?? artistName
            if let albumID = song.albumId ?? song.parent {
                albumIDsByArtist[artistID, default: []].insert(albumID)
            }
            if artistsByID[artistID] == nil {
                artistsByID[artistID] = Artist(id: artistID, name: artistName, albumCount: 1, artistImageUrl: nil)
            }
        }

        for album in library.albums {
            guard let albumArtist = album.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !albumArtist.isEmpty else { continue }
            let artistID = album.artistId ?? albumArtist
            albumIDsByArtist[artistID, default: []].insert(album.id)
            if artistsByID[artistID] == nil {
                artistsByID[artistID] = Artist(id: artistID, name: albumArtist, albumCount: 1, artistImageUrl: nil)
            }
        }

        return artistsByID.values.map { artist in
            let count = albumIDsByArtist[artist.id]?.count ?? 1
            return Artist(id: artist.id, name: artist.name, albumCount: count, artistImageUrl: artist.artistImageUrl)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func extractSongArtistName(_ song: SubsonicSong) -> String? {
        if let trimmedArtist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedArtist.isEmpty {
            return trimmedArtist
        }
        if let trimmedAlbumArtist = song.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedAlbumArtist.isEmpty {
            return trimmedAlbumArtist
        }
        if song.effectiveAlbumArtist != "Unknown Artist" {
            return song.effectiveAlbumArtist
        }
        return nil
    }

    func offlineArtistIndexes(from songs: [SubsonicSong]) -> [ArtistIndex] {
        let allArtists = offlineArtists(from: songs)
        let grouped = Dictionary(grouping: allArtists) { artist -> String in
            let first = artist.name.prefix(1).uppercased()
            return first.isEmpty ? "#" : first
        }
        let sortedKeys = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return sortedKeys.map { key in
            ArtistIndex(name: key, artist: grouped[key])
        }
    }

    func coverArtForArtist(_ artist: Artist) -> String? {
        let artistID = artist.id
        let artistName = artist.name
        if let song = downloadedSongs.first(where: {
            $0.artistId == artistID ||
            $0.albumArtistId == artistID ||
            ($0.artist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame) ||
            ($0.albumArtist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame)
        }), let cover = song.coverArt {
            return cover
        }
        if let album = library.albums.first(where: {
            $0.artistId == artistID ||
            ($0.artist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame)
        }), let cover = album.coverArt {
            return cover
        }
        return nil
    }

    func offlineAlbums(from songs: [SubsonicSong]) -> [SubsonicAlbum] {
        let grouped = Dictionary(grouping: songs, by: { $0.albumId ?? $0.parent ?? $0.album ?? $0.id })
        return grouped.compactMap { albumIdentifier, tracks in
            guard let first = tracks.first else { return nil }
            return SubsonicAlbum(
                id: albumIdentifier,
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

    var shouldShowLoginView: Bool {
        isAddingServer || (
            !isLaunching &&
            connectionState == .unconfigured &&
            !isSwitchingServer
        )
    }
}
