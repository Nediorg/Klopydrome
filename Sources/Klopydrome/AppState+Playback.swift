import Foundation
import NavidromeClient

// MARK: - Playback engine routing

// Playback runs on one of two engines. The MPV engine (default, selected in
// Settings) decodes every format the server can send through libmpv and seeks
// HTTP streams sample-accurately by range-requesting the exact byte offset, so
// lyric highlights stay locked to the audio. AVFoundation is the opt-out engine
// for the rare format mpv can't decode.
extension AppState {
    /// Resolves the source for the muted MPV preloader. A completed disk-cache
    /// copy is preferred; otherwise MPV begins buffering the regular stream.
    func setUpNextTrackPreloading() {
        player.automix.onNextTrackPreloadRequest = { [weak self] song in
            guard let self, self.usesMPVEngine else { return nil }
            return self.cachedURL(for: song) ?? self.streamURL(for: song)
        }
        player.automix.onCachedTrackURLRequest = { [weak self] song in
            self?.cachedURL(for: song)
        }
    }
    /// True when playback routes through the MPV engine (the default, or the
    /// user's explicit choice). When false, AVPlayer is used.
    var usesMPVEngine: Bool { serverConfig.effectivePlaybackEngine == .mpv }

    /// The suffix the chosen engine will actually decode for this song. A
    /// user-chosen transcode codec wins; the MPV engine decodes any source
    /// format natively, so only the AVPlayer engine needs the server to
    /// transcode unsupported formats to mp3.
    func effectiveSuffix(for song: SubsonicSong) -> String {
        if let format = serverConfig.format, !format.isEmpty { return format }
        if !usesMPVEngine, PlaybackFormat.needsTranscode(song.suffix) { return "mp3" }
        return (song.suffix ?? "mp3").lowercased()
    }

    /// Builds a stream URL that will actually play. Honors a user-chosen codec;
    /// with the MPV engine the original stream is requested (it decodes
    /// everything itself); only the AVPlayer engine asks the server to
    /// transcode source formats it can't decode natively.
    func streamURL(for song: SubsonicSong) -> URL? {
        guard let client else { return nil }
        // MPV probes duration from the demuxer; an estimated Content-Length
        // (bitrate*duration) for VBR transcodes can make the engine under-report
        // until fully probed. Prefer chunked without length for MPV.
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

    /// The suffix used when downloading a track to the stream cache.
    /// Honors `downloadTranscoded` preference: if true, uses the streaming transcode format;
    /// if false, uses the original file format (song.suffix).
    func downloadSuffix(for song: SubsonicSong) -> String {
        if serverConfig.effectiveDownloadTranscoded {
            return effectiveSuffix(for: song)
        }
        return (song.suffix ?? "mp3").lowercased()
    }

    /// The remote URL used when downloading a track to the stream cache.
    /// If `downloadTranscoded` is true, downloads using the streaming transcode settings.
    /// If false, requests raw original audio bytes without transcoding.
    func downloadStreamURL(for song: SubsonicSong) -> URL? {
        guard let client else { return nil }
        if serverConfig.effectiveDownloadTranscoded {
            return streamURL(for: song)
        }
        return client.downloadURL(songId: song.id, maxBitRate: 0, format: "raw")
            ?? client.streamURL(songId: song.id, maxBitRate: 0, estimateContentLength: false)
    }

    /// Starts playback for a song.
    /// - Returns `true` when playback has been started, `false` when nothing
    ///   loaded (no URL could be built).
    func startLocalOrBuffered(_ song: SubsonicSong) -> Bool {
        setUpNextTrackPreloading()
        // Cached copy — play it directly through the chosen engine.
        if let cached = cachedURL(for: song) {
            play(url: cached)
            return true
        }

        // Record the same MPV playback stream only while it naturally reaches
        // EOF. There is no second URLSession request, and a skipped or sought
        // track leaves no persistent partial file.
        guard let url = streamURL(for: song) else { return false }
        let streamRecordURL = beginAutomaticPlaybackCache(for: song)
        play(url: url, streamRecordURL: streamRecordURL)
        return true
    }

    /// Routes a resolved URL to the playback engine chosen in Settings: MPV
    /// for every format (default), or AVPlayer when the user opted out.
    func play(url: URL, streamRecordURL: URL? = nil) {
        if usesMPVEngine {
            player.playMPV(url, streamRecordURL: streamRecordURL)
        } else {
            player.playURL(url)
        }
    }

    /// Sets up playback engine event callbacks and Discord RPC status hooks.
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

    /// Queues multiple songs to play immediately after the current track.
    func playNext(_ songs: [SubsonicSong]) {
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        var queue = player.queue
        let insertAt = min(player.currentIndex + 1, queue.count)
        queue.insert(contentsOf: songs, at: insertAt)
        player.queue = queue
    }

    /// Queues multiple songs at the end of the current play queue.
    func playLater(_ songs: [SubsonicSong]) {
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        player.queue.append(contentsOf: songs)
    }

    func play(
        _ songs: [SubsonicSong],
        at index: Int = 0,
        contextTitle: String? = nil,
        context: PlaybackContext? = nil
    ) {
        let resolvedContext: PlaybackContext? = {
            if let context { return context }
            if let contextTitle, !contextTitle.isEmpty { return .general(title: contextTitle) }
            return nil
        }()
        player.setQueue(songs, startAt: index, context: resolvedContext)
    }

    func play(
        _ song: SubsonicSong,
        in queue: [SubsonicSong],
        contextTitle: String? = nil,
        context: PlaybackContext? = nil
    ) {
        let resolvedContext: PlaybackContext? = {
            if let context { return context }
            if let contextTitle, !contextTitle.isEmpty { return .general(title: contextTitle) }
            return nil
        }()
        if let index = queue.firstIndex(where: { $0.id == song.id }) {
            player.setQueue(queue, startAt: index, context: resolvedContext)
        } else {
            player.setQueue([song], startAt: 0, context: resolvedContext)
        }
    }

    func playShuffled(
        _ songs: [SubsonicSong],
        contextTitle: String? = nil,
        context: PlaybackContext? = nil
    ) {
        guard !songs.isEmpty else { return }
        let resolvedContext: PlaybackContext? = {
            if let context { return context }
            if let contextTitle, !contextTitle.isEmpty { return .general(title: contextTitle) }
            return nil
        }()
        player.setQueue(songs.shuffled(), startAt: 0, context: resolvedContext)
    }

    func play(_ album: SubsonicAlbum) {
        let localTracks = downloadedSongs.filter { ($0.albumId ?? $0.parent) == album.id }
        if !localTracks.isEmpty {
            play(localTracks, context: .album(album))
            return
        }
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: album.id))?.song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { play(songs, context: .album(album)) }
        }
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

    func playNext(_ album: SubsonicAlbum) {
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: album.id))?.song ?? []
            guard !songs.isEmpty else { return }
            var queue = await MainActor.run { self.player.queue }
            queue.append(contentsOf: songs)
            await MainActor.run { self.player.queue = queue }
        }
    }

    func playNext(_ song: SubsonicSong) {
        guard !player.queue.isEmpty else {
            play([song], at: 0)
            return
        }
        var queue = player.queue
        let insertAt = (player.currentIndex + 1) % queue.count
        queue.insert(song, at: insertAt)
        player.queue = queue
    }

    func playLater(_ song: SubsonicSong) {
        guard !player.queue.isEmpty else {
            play([song], at: 0)
            return
        }
        player.queue.append(song)
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
            player.lastError = "Этот трек не загружен для оффлайн-прослушивания.".localized
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
