import Foundation
import NavidromeClient

extension AppState {
    func setUpNextTrackPreloading() {
        player.automix.onNextTrackPreloadRequest = { [weak self] song in
            guard let self, self.usesMPVEngine else { return nil }
            return self.cachedURL(for: song) ?? self.streamURL(for: song)
        }
        player.automix.onCachedTrackURLRequest = { [weak self] song in
            self?.cachedURL(for: song)
        }
    }
    var usesMPVEngine: Bool { serverConfig.effectivePlaybackEngine == .mpv }

    func effectiveSuffix(for song: SubsonicSong) -> String {
        if let format = serverConfig.format, !format.isEmpty { return format }
        if !usesMPVEngine, PlaybackFormat.needsTranscode(song.suffix) { return "mp3" }
        return (song.suffix ?? "mp3").lowercased()
    }

    func streamURL(for song: SubsonicSong) -> URL? {
        guard let client else { return nil }
        let estimate = !usesMPVEngine
        if let format = serverConfig.format, !format.isEmpty {
            return client.streamURL(
                songId: song.id,
                maxBitRate: serverConfig.maxBitRate,
                format: format,
                estimateContentLength: estimate
            )
        }
        if !usesMPVEngine, PlaybackFormat.needsTranscode(song.suffix) {
            return client.streamURL(
                songId: song.id,
                maxBitRate: serverConfig.maxBitRate,
                format: "mp3",
                estimateContentLength: estimate
            )
        }
        return client.streamURL(
            songId: song.id,
            maxBitRate: serverConfig.maxBitRate,
            estimateContentLength: estimate
        )
    }

    func downloadSuffix(for song: SubsonicSong) -> String {
        if serverConfig.effectiveDownloadTranscoded {
            return effectiveSuffix(for: song)
        }
        return (song.suffix ?? "mp3").lowercased()
    }

    func downloadStreamURL(for song: SubsonicSong) -> URL? {
        guard let client else { return nil }
        if serverConfig.effectiveDownloadTranscoded {
            return streamURL(for: song)
        }
        return client.downloadURL(songId: song.id, maxBitRate: 0, format: "raw")
            ?? client.streamURL(songId: song.id, maxBitRate: 0, estimateContentLength: false)
    }

    func startLocalOrBuffered(_ song: SubsonicSong) -> Bool {
        setUpNextTrackPreloading()
        if let cached = cachedURL(for: song) {
            play(url: cached)
            return true
        }

        guard let url = streamURL(for: song) else { return false }
        let streamRecordURL = beginAutomaticPlaybackCache(for: song)
        play(url: url, streamRecordURL: streamRecordURL)
        return true
    }

    func play(url: URL, streamRecordURL: URL? = nil) {
        if usesMPVEngine {
            player.playMPV(url, streamRecordURL: streamRecordURL)
        } else {
            player.playURL(url)
        }
    }

    func configurePlayerLifecycle() {
        player.onDiscordPresenceUpdate = { [weak self] in
            self?.refreshDiscordRichPresence()
        }
        DiscordRPCTransport.onStatusChange = { [weak self] status in
            Task { @MainActor in
                guard let self, self.discordConnectionStatus != status else { return }
                self.discordConnectionStatus = status
            }
        }
        player.onTrackRequest = { [weak self] song in
            self?.startCurrent(song)
        }
        player.onStreamRecordFinished = { [weak self] url in
            Task { await self?.finishAutomaticPlaybackCache(at: url) }
        }
        player.onTrackEnded = { [weak self] in
            guard let self else { return }
            self.discordSnoozeSongID = nil
            if self.scrobblingEnabled, let ended = self.player.currentSong {
                let id = ended.id
                Task { try? await self.client?.scrobble(id: id, submission: true) }
            }
            self.player.trackDidFinish()
        }
        player.onTrackCrossfaded = { [weak self] ended in
            guard let self else { return }
            self.discordSnoozeSongID = nil
            if self.scrobblingEnabled {
                let id = ended.id
                Task { try? await self.client?.scrobble(id: id, submission: true) }
            }
        }
    }

    func playNext(_ song: SubsonicSong) {
        playNext([song])
    }

    func playNext(_ songs: [SubsonicSong]) {
        guard !songs.isEmpty else { return }
        let playable = isOfflineSession ? songs.filter { isCached($0) } : songs
        guard !playable.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(playable, at: 0)
            return
        }
        var queue = player.queue
        let insertAt = min(player.currentIndex + 1, queue.count)
        queue.insert(contentsOf: playable, at: insertAt)
        player.queue = queue
    }

    func playLater(_ song: SubsonicSong) {
        playLater([song])
    }

    func playLater(_ songs: [SubsonicSong]) {
        guard !songs.isEmpty else { return }
        let playable = isOfflineSession ? songs.filter { isCached($0) } : songs
        guard !playable.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(playable, at: 0)
            return
        }
        player.queue.append(contentsOf: playable)
    }

    func play(
        _ songs: [SubsonicSong],
        at index: Int = 0,
        context: PlaybackContext? = nil
    ) {
        guard !songs.isEmpty else { return }
        let playableSongs: [SubsonicSong]
        let playIndex: Int
        if isOfflineSession {
            let targetSong = songs.indices.contains(index) ? songs[index] : nil
            playableSongs = songs.filter { isCached($0) }
            guard !playableSongs.isEmpty else { return }
            if let targetSong, let matchedIndex = playableSongs.firstIndex(where: { $0.id == targetSong.id }) {
                playIndex = matchedIndex
            } else {
                playIndex = 0
            }
        } else {
            playableSongs = songs
            playIndex = min(max(0, index), songs.count - 1)
        }
        player.setQueue(playableSongs, startAt: playIndex, context: context)
    }

    func play(
        _ song: SubsonicSong,
        in queue: [SubsonicSong] = [],
        context: PlaybackContext? = nil
    ) {
        if queue.isEmpty {
            play([song], at: 0, context: context)
            return
        }
        let index = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        play(queue, at: index, context: context)
    }

    func playShuffled(
        _ songs: [SubsonicSong],
        context: PlaybackContext? = nil
    ) {
        guard !songs.isEmpty else { return }
        let playable = isOfflineSession ? songs.filter { isCached($0) } : songs
        guard !playable.isEmpty else { return }
        player.setQueue(playable.shuffled(), startAt: 0, context: context)
    }

    func albumSongs(_ album: SubsonicAlbum) async -> [SubsonicSong] {
        let localTracks = downloadedSongs.filter { ($0.albumId ?? $0.parent) == album.id }
        if !localTracks.isEmpty { return localTracks }
        guard let client else { return [] }
        return (try? await client.getAlbum(id: album.id))?.song ?? []
    }

    func play(_ album: SubsonicAlbum) {
        Task {
            let songs = await albumSongs(album)
            guard !songs.isEmpty else { return }
            await MainActor.run { play(songs, at: 0, context: .album(album)) }
        }
    }

    func playShuffled(_ album: SubsonicAlbum) async {
        let songs = await albumSongs(album)
        guard !songs.isEmpty else { return }
        playShuffled(songs, context: .album(album))
    }

    func playNext(_ album: SubsonicAlbum) async {
        let songs = await albumSongs(album)
        guard !songs.isEmpty else { return }
        playNext(songs)
    }

    func playLater(_ album: SubsonicAlbum) async {
        let songs = await albumSongs(album)
        guard !songs.isEmpty else { return }
        playLater(songs)
    }

    func addAlbum(_ album: SubsonicAlbum, to playlistID: String) async {
        let songs = await albumSongs(album)
        guard !songs.isEmpty else { return }
        await addToPlaylist(songs, playlistID: playlistID)
    }

    func playStation(from song: SubsonicSong) {
        guard let client else {
            play([song])
            return
        }
        Task {
            var similar = (try? await client.getSimilarSongs2(id: song.id, count: 50)) ?? []
            if similar.isEmpty, let artistId = song.artistId, !artistId.isEmpty {
                similar = (try? await client.getTopSongs(artistId: artistId, count: 50)) ?? []
            }
            if similar.isEmpty, let albumId = song.albumId {
                similar = (try? await client.getAlbum(id: albumId))?.song ?? []
            }
            var stationQueue = [song]
            stationQueue.append(contentsOf: similar.filter { $0.id != song.id })
            await MainActor.run {
                play(stationQueue, at: 0)
            }
        }
    }

    func saveQueueToServer() {
        guard queuePersistenceEnabled, let client,
              !player.queue.isEmpty else { return }
        Task {
            let ids = player.queue.map(\.id)
            try? await client.savePlayQueue(
                songIds: ids,
                currentId: player.currentSong?.id,
                position: player.currentTime * 1000.0
            )
        }
    }

    func restoreQueueFromServer() async {
        guard queuePersistenceEnabled, let client else { return }
        guard let queue = try? await client.getPlayQueue(),
              let entries = queue.entry, !entries.isEmpty else { return }
        let restored = entries
        let targetIndex: Int
        if let current = queue.current, let index = restored.firstIndex(where: { $0.id == current }) {
            targetIndex = index
        } else {
            targetIndex = 0
        }
        await MainActor.run {
            let wasLoaded = player.hasLoadedItem
            let previousID = player.currentSong?.id
            player.queue = restored
            player.currentIndex = targetIndex
            if !wasLoaded || previousID != player.currentSong?.id {
                player.startCurrent(autoPlay: false)
                if let posMs = queue.position, posMs > 0 {
                    player.seek(to: Double(posMs) / 1000.0)
                }
                player.pause()
            }
            saveQueueToServer()
        }
    }

    func startCurrent(_ song: SubsonicSong) {
        if discordSnoozeSongID != song.id {
            discordSnoozeSongID = nil
        }
        currentCacheTask?.cancel()
        lyricsTask?.cancel()
        scrobbleTask?.cancel()

        lyricsTask = Task { await lyrics.load(song: song, client: client, cache: cache) }

        if let client {
            saveQueueToServer()
            if scrobblingEnabled {
                scrobbleTask = Task { try? await client.scrobble(id: song.id, submission: false) }
            }
        }

        if startLocalOrBuffered(song) { return }
        guard let url = streamURL(for: song) else {
            player.lastError = "This track is not downloaded for offline listening.".localized
            player.isLoading = false
            return
        }
        play(url: url)
        if serverConfig.cacheEnabled {
            activeCacheTasks.insert(song.id)
            updateCachingFlag()
            currentCacheTask = Task { await cacheCurrentInBackground(song) }
        }
    }

    private func cacheCurrentInBackground(_ song: SubsonicSong) async {
        defer {
            activeCacheTasks.remove(song.id)
            updateCachingFlag()
        }
        try? await downloadToCache(song)
    }

    private func updateCachingFlag() {
        player.isCaching = activeCacheTasks.contains(player.currentSong?.id ?? "")
    }

    func candidateSuffixes(for song: SubsonicSong) -> [String] {
        var suffixes: [String] = []
        let download = downloadSuffix(for: song)
        if !download.isEmpty { suffixes.append(download) }
        let effective = effectiveSuffix(for: song)
        if !effective.isEmpty && !suffixes.contains(effective) { suffixes.append(effective) }
        if let raw = song.suffix?.lowercased(), !raw.isEmpty && !suffixes.contains(raw) {
            suffixes.append(raw)
        }
        for fallback in ["mp3", "flac", "m4a", "opus", "ogg", "aac", "wav"] where !suffixes.contains(fallback) {
            suffixes.append(fallback)
        }
        return suffixes
    }

    func cachedURL(for song: SubsonicSong) -> URL? {
        guard let cache else { return nil }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            let url = cache.fileURL(for: .streams, key: key)
            if cachedStreamKeysSeeded {
                if cachedStreamKeys.contains(url.lastPathComponent) {
                    return url
                }
            } else if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func isCached(_ song: SubsonicSong) -> Bool {
        guard cache != nil else { return false }
        if !cachedStreamKeysSeeded { Task { await seedCachedStreamKeys() } }
        guard !cachedStreamKeys.isEmpty else { return false }
        let primaryKey = CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
        if let name = cacheFileName(for: primaryKey), cachedStreamKeys.contains(name) {
            return true
        }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            if let name = cacheFileName(for: key), cachedStreamKeys.contains(name) {
                return true
            }
        }
        return false
    }

    private func streamKey(for song: SubsonicSong) -> String {
        CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
    }

    private func cacheFileName(for key: String) -> String? {
        guard let cache else { return nil }
        return cache.fileURL(for: .streams, key: key).lastPathComponent
    }
}
