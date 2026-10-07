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

    func setupOfflineRepository(host: String) async {
        if offlineRepository != nil && currentOfflineHost == host {
            return
        }
        guard let repository = try? SwiftDataOfflineRepository.makeDefault(serverHost: host) else {
            return
        }
        self.offlineRepository = repository
        self.currentOfflineHost = host
        let cacheRoot = CacheManager.root(forServer: host)
        await OfflineMigration.migrateIfNeeded(cacheRoot: cacheRoot, repository: repository)
    }

    /// Restores the in-memory offline download list from the on-disk catalog.
    /// Runs on EVERY connection (online and offline) so the Downloads popover
    /// and the offline bookkeeping reflect what is actually on disk. It must
    /// NOT touch `library`: after an online `connect()` the library was just
    /// reset to a fresh `LibraryCache()`, and stamping it with the offline
    /// subset here is what made the Home shelves stay empty and every tab show
    /// only downloaded songs, never re-fetching from the server.
    func restoreOfflineCatalog() async {
        guard let offlineRepository else { return }
        if !cachedStreamKeysSeeded {
            await seedCachedStreamKeys()
        }
        let tracks = (try? await offlineRepository.fetchDownloadedTracks()) ?? []
        let songs = tracks.filter { isCached($0) }
        replaceDownloadedSongs(songs)
    }

    var effectiveUsername: String {
        if let username = client?.config.username, !username.isEmpty {
            return username
        }
        return serverConfig.username
    }

    /// Stamps the library cache with the persisted offline snapshot. Only used
    /// inside `beginOfflineSession()`: an offline session has no server, so the
    /// tabs must render the saved songs/albums/playlists and mark every store
    /// as loaded (otherwise each tab would show its spinner forever).
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
        library.favoritesSongs = songs
        library.favoritesLoaded = true
        library.playlists = playlists
        library.playlistsLoaded = true
        library.artistIndexes = offlineArtistIndexes(from: songs)
        library.artistIndexesLoaded = true
        library.homeShelves = [:]
        library.homeShelvesLoaded = true
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
            let hasAnyDownloaded = detail.song?.contains(where: { cachedURL(for: $0) != nil }) ?? false
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
        let hasAnyDownloaded = detail.entry?.contains(where: { cachedURL(for: $0) != nil }) ?? false
        guard hasAnyDownloaded else { return nil }
        return detail
    }

    func beginOfflineSession() async -> Bool {
        isPreparingOfflineSession = true
        defer { isPreparingOfflineSession = false }

        guard !serverConfig.url.isEmpty,
              let host = URL(string: serverConfig.url)?.host else {
            return false
        }

        let offlineCache = CacheManager(rootURL: CacheManager.root(forServer: host))
        cache = offlineCache
        resetCacheState()
        await applyCacheLimits()
        await seedCachedStreamKeys()
        await setupOfflineRepository(host: host)

        let downloadedTracks = (try? await offlineRepository?.fetchDownloadedTracks())?
            .filter { isCached($0) } ?? []
        let hasDownloadedTracks = !downloadedTracks.isEmpty
        if !hasDownloadedTracks && !serverConfig.effectiveForceOfflineMode {
            cache = nil
            resetCacheState()
            return false
        }
        await restoreOfflineLibrary()

        if !isOfflineSession {
            pruneOfflineNavigation()
        }
        isOfflineSession = true
        return true
    }

    private func pruneOfflineNavigation() {
        if nav.selected == .search || nav.selected == .genres {
            nav.selected = .songs
        }
        if let selected = nav.selectedPlaylist, !library.playlists.contains(where: { $0.id == selected.id }) {
            nav.selectedPlaylist = nil
        }
        nav.history.removeAll { [weak self] destination in
            guard let self else { return true }
            return !self.isDestinationAvailableOffline(destination)
        }
    }

    private func isDestinationAvailableOffline(_ destination: NavigationState.Destination) -> Bool {
        switch destination {
        case .album(let album):
            return library.albums.contains(where: { $0.id == album.id })
        case .playlist(let playlist):
            return library.playlists.contains(where: { $0.id == playlist.id })
        case .smartPlaylist, .genre:
            return false
        case .artist(let artist):
            return library.artistIndexes.contains { index in
                index.artist?.contains(where: { $0.id == artist.id }) ?? false
            }
        case .song(let song):
            return isCached(song)
        }
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

    /// Determines whether the login overlay should be displayed over the main view.
    /// Returns false while launching, connected, offline, preparing an offline session,
    /// or actively reconnecting.
    var shouldShowLoginView: Bool {
        !isLaunching &&
        !isConnected &&
        !isOfflineSession &&
        !isPreparingOfflineSession &&
        !isReconnecting &&
        !isBackgroundReconnecting
    }
}
