import Foundation
import NavidromeClient
import Observation
import os
import SwiftUI

@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class AppState {
    var client: SubsonicClient?
    /// Navidrome native-REST client, used only for smart-playlist rule editing
    /// (the Subsonic API has no rules endpoint). Created on connect, released on
    /// disconnect, so it always matches the active server connection.
    var navidrome: NavidromeAPI?
    var cache: CacheManager?
    var serverConfig: ServerConfig = .empty

    var player = Player()
    let discordRichPresence = DiscordRichPresence()
    /// Latest Discord RPC connection state, surfaced in Settings so a silent
    /// "no presence in Discord" has a visible diagnosis.
    var discordConnectionStatus: DiscordRPCTransport.ConnectionStatus = .idle
    @ObservationIgnored var discordAlbumArtworkURLs: [String: URL] = [:]
    @ObservationIgnored var discordArtworkUnavailableAlbumIDs: Set<String> = []
    @ObservationIgnored var discordArtworkLoadingAlbumIDs: Set<String> = []
    var lyrics = LyricsStore()
    var nav = NavigationState()
    var library = LibraryCache()
    /// Shared progress for detail views and playback actions loading the same
    /// playlist. SwiftUI observes snapshots while task identity stays private.
    var playlistLoadStates: [String: PlaylistLoadState] = [:]
    @ObservationIgnored var playlistLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var playlistLoadTokens: [String: UUID] = [:]

    /// Genres known to the server, loaded lazily for the rule editor's picker.
    var availableGenres: [Genre] = []

    /// Fetches the server's genre list if not already loaded (best-effort).
    func loadGenresIfNeeded() async {
        guard availableGenres.isEmpty, let client else { return }
        if let genres = try? await client.getGenres() {
            availableGenres = genres
        }
    }

    /// Evaluates smart-playlist queries against a full-library pool (built once
    /// per connection). Rebuilt on connect so it always uses the active client.
    private(set) var smartPlaylistEngine: SmartPlaylistEngine?

    var isConnecting = false
    var connectionError: String?
    var isOfflineSession = false
    /// True while a foreground-activation auto-reconnect is in flight (not a
    /// manual login): the login overlay stays hidden for it.
    var isBackgroundReconnecting = false
    /// Last foreground-refresh run; initialized to now so the launch-time
    /// activation (owned by the launch flow) is skipped by the debounce.
    var lastForegroundRefresh = Date()

    var cachedKeychainPassword: String?
    var didReadKeychainPassword = false
    var automaticPlaybackRecording: (song: SubsonicSong, temporaryURL: URL)?

    /// True until the first connection decision (reconnect attempt or no saved
    /// config) completes. ContentView shows a loading gate while it's true so the
    /// UI never flashes LoginView before the app knows whether to auto-connect.
    var isLaunching = true

    /// Present the "new playlist" sheet at the app root. Hoisting this here
    /// (instead of inside `AddToPlaylistMenu`) is what makes the modal actually
    /// appear: a `.sheet` attached to a menu's transient view tree is torn down
    /// as soon as the menu closes, so the presentation never happens.
    var isCreatingPlaylist = false
    var creatingPlaylistSongs: [SubsonicSong] = []

    /// Present the "share" sheet at the app root. Hoisting this here (instead of
    /// inside a context-menu component) is what makes the modal actually appear:
    /// a `.sheet` attached to a menu's transient view tree is torn down as soon
    /// as the menu closes, so the presentation never happens. The sheet is
    /// attached in `MainView` and reads this value.
    var shareTarget: ShareTarget?

    var showLyrics = true
    var queuePanelVisible = false
    var scrobblingEnabled = true

    /// Song ids currently being downloaded into the stream cache.
    var downloadingSongIDs: Set<String> = []

    /// Songs currently downloading, in start order, for the Downloads popover.
    /// Kept in sync with `downloadingSongIDs` (dedupes programmatic cache hits).
    var downloadingSongs: [SubsonicSong] = []

    /// Download progress (0...1) per song id. Updated incrementally by
    /// `downloadToCache` so the popover can show live progress.
    var downloadProgress: [String: Double] = [:]

    /// Songs full-discarded to the offline cache and still present on disk.
    /// Populated as downloads complete and pruned on removal. Order is
    /// newest-first so the Downloads popover reads naturally.
    private(set) var downloadedSongs: [SubsonicSong] = []

    /// Aggregate download progress (0...1) across active transfers, or nil when
    /// nothing is downloading. Drives the status bar under the toolbar icon.
    var overallDownloadProgress: Double? {
        guard !downloadingSongIDs.isEmpty else { return nil }
        let values = downloadingSongIDs.compactMap { downloadProgress[$0] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Whether the Downloads affordance should be visible at all: any active
    /// transfer or any completed offline songs.
    var hasDownloadContent: Bool {
        !downloadingSongIDs.isEmpty || !downloadedSongs.isEmpty
    }

    /// Rule-based playlists stored locally (Subsonic can't persist these).
    var smartPlaylists: [SmartPlaylist] = []

    /// Playlist ids the user has "added to favourites" locally. Subsonic's star
    /// endpoint has no playlist kind, so this is a client-side pins in UserDefaults.
    var followedPlaylistIDs: Set<String> = [] {
        didSet { saveFollowedPlaylists() }
    }

    /// Playlist ids the user last added to, newest first (capped). Surfaced in
    /// the "Добавить в плейлист" submenu above the full playlists list.
    var recentPlaylistIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentPlaylistsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentPlaylistsKey) }
    }

    /// Whether the play queue is synced to the server and restored on launch.
    var queuePersistenceEnabled = false {
        didSet { UserDefaults.standard.set(queuePersistenceEnabled, forKey: queuePersistenceKey) }
    }

    private var activeCacheTasks: Set<String> = []
    /// Songs the user has asked to cancel mid-download; checked in the batch
    /// loop so a cancelled song is skipped after its in-flight write stops.
    private var cancelledDownloads: Set<String> = []
    /// Stream-cache keys known to exist on disk. Seeded once from a directory
    /// scan and maintained on download/remove, so `isCached(_:)` is O(1) and a
    /// song list never performs a `FileManager` probe per visible row. LRU
    /// eviction can momentarily leave a stale entry; playback still verifies
    /// with the authoritative `cachedURL(for:)` file check.
    var cachedStreamKeys: Set<String> = []
    var cachedStreamKeysSeeded = false
    private let configKey = "serverConfig"
    let smartPlaylistsKey = "smartPlaylists"
    let followedKey = "followedPlaylists"
    private let queuePersistenceKey = "queuePersistenceEnabled"
    /// Most-recently-used playlist ids, newest first (capped); shown in the
    /// "Добавить в плейлист" submenu above the full playlists list.
    private let recentPlaylistsKey = "recentPlaylists"

    /// Background cache download for the currently playing song; cancelled when
    /// the track changes so a stale download doesn't keep streaming.
    var currentCacheTask: Task<Void, Never>?
    /// Lyrics fetch for the current song; cancelled when the track changes.
    private var lyricsTask: Task<Void, Never>?
    /// Scrobble-start report for the current song; cancelled when the track changes.
    private var scrobbleTask: Task<Void, Never>?

    var isConnected: Bool { client != nil }

    /// SwiftUI appearance matching the chosen theme (GUIDELINES §16).
    var appearance: ColorScheme? {
        switch serverConfig.theme {
        case .dark: return .dark
        case .light: return .light
        default: return nil
        }
    }

    init() {
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
            if self.scrobblingEnabled, let ended = self.player.currentSong {
                let id = ended.id
                Task { try? await self.client?.scrobble(id: id, submission: true) }
            }
            self.player.trackDidFinish()
        }
        player.onTrackCrossfaded = { [weak self] ended in
            guard let self, self.scrobblingEnabled else { return }
            let id = ended.id
            Task { try? await self.client?.scrobble(id: id, submission: true) }
        }
        loadPersisted()
        restorePlaybackExitPreferences()
        player.configureAutomix(
            enabled: serverConfig.effectiveAutomixEnabled,
            fadeDuration: serverConfig.effectiveAutomixFadeDuration
        )
        player.configureReplayGain(
            mode: serverConfig.effectiveReplayGainMode,
            preampDB: serverConfig.effectiveReplayGainPreampDB
        )
        player.configureSilenceTrim(mode: serverConfig.effectiveSilenceTrimMode)
        player.configureNextTrackPreloading(
            enabled: serverConfig.effectiveNextTrackPreloadingEnabled
        )
        loadSmartPlaylists()
        loadFollowedPlaylists()
        queuePersistenceEnabled = UserDefaults.standard.object(forKey: queuePersistenceKey) as? Bool ?? false
    }

    // MARK: Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            return
        }
        serverConfig = config
        player.configureAutomix(
            enabled: config.effectiveAutomixEnabled,
            fadeDuration: config.effectiveAutomixFadeDuration
        )
        player.configureReplayGain(
            mode: config.effectiveReplayGainMode,
            preampDB: config.effectiveReplayGainPreampDB
        )
        player.configureSilenceTrim(mode: config.effectiveSilenceTrimMode)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(serverConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Persists the current server config (called when settings change).
    func saveSettings() {
        persist()
    }

    func reconnectIfPossible() async {
        defer { isLaunching = false }
        guard serverConfig.url.isEmpty == false else { return }
        guard let password = passwordForLoginPrefill() else {
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни."
            }
            return
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.connect(url: self.serverConfig.url, username: self.serverConfig.username,
                                           password: password, authMode: self.serverConfig.authMode)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    throw CancellationError()
                }
                try await group.next()
                group.cancelAll()
            }
        } catch is CancellationError {
            connectionError = "Нет соединения с сервером."
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни."
            }
        } catch {
            connectionError = error.localizedDescription
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни."
            }
        }
    }

    // MARK: Connection

    func connect(url: String, username: String, password: String,
                 authMode: AuthMode, cacheEnabled: Bool? = nil, allowInsecureHTTP: Bool = false) async throws {
        isConnecting = true
        defer { isConnecting = false }
        do {
            let base = try normalize(url: url, allowInsecureHTTP: allowInsecureHTTP)
            let config = SubsonicConfig(baseURL: base, username: username,
                                        password: password, authMode: authMode)
            let client = SubsonicClient(config: config)
            try await client.ping()

            var updatedConfig = serverConfig
            updatedConfig.url = url
            updatedConfig.username = username
            updatedConfig.authMode = authMode
            updatedConfig.cacheEnabled = cacheEnabled ?? updatedConfig.cacheEnabled

            // New server (or reconnect): drop all cached library data from any
            // previous connection so no stale songs/albums leak into the new one.
            cancelPlaylistLoads()
            library = LibraryCache()
            withMutation(keyPath: \.starOverrides) { starOverrides = [:] }
            withMutation(keyPath: \.ratingOverrides) { ratingOverrides = [:] }

            self.client = client
            self.navidrome = NavidromeAPI(baseURL: base, username: username, password: password)
            self.cache = CacheManager(rootURL: CacheManager.root(forServer: base.host ?? "default"))
            // Disk-persist the smart-playlist pool so a new session's first
            // compute can load it instead of re-crawling the whole library.
            self.smartPlaylistEngine = SmartPlaylistEngine(repo: CachedLibraryRepo(client: client, cache: self.cache))
            resetCacheState()
            Task { await self.seedCachedStreamKeys() }
            serverConfig = updatedConfig
            isOfflineSession = false
            await applyCacheLimits()
            await restoreOfflineCatalog()
            self.connectionError = nil
            persist()
            if !didReadKeychainPassword || cachedKeychainPassword != password {
                try? KeychainStore.save(password: password, account: username)
            }
            cachedKeychainPassword = password
            didReadKeychainPassword = true
            CoverArtStore.shared.configure(client: client, cache: self.cache,
                                           coverResolution: serverConfig.coverResolution ?? .high)
            if queuePersistenceEnabled {
                await restoreQueueFromServer()
            }
        } catch {
            connectionError = error.localizedDescription
            self.client = nil
            throw error
        }
    }

    func disconnect() {
        discordRichPresence.clear()
        discordConnectionStatus = .idle
        discordAlbumArtworkURLs = [:]
        discordArtworkUnavailableAlbumIDs = []
        discordArtworkLoadingAlbumIDs = []
        cancelAutomaticPlaybackCache()
        cancelPlaylistLoads()
        isOfflineSession = false
        cachedKeychainPassword = nil
        didReadKeychainPassword = false
        player.setQueue([])
        client = nil
        navidrome = nil
        cache = nil
        lyrics.reset()
        currentCacheTask?.cancel()
        currentCacheTask = nil
        smartPlaylistEngine = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        scrobbleTask?.cancel()
        scrobbleTask = nil
        downloadingSongIDs = []
        downloadingSongs = []
        downloadProgress = [:]
        downloadedSongs = []
        cancelledDownloads = []
        activeCacheTasks = []
        cachedStreamKeys = []
        cachedStreamKeysSeeded = false
        player.isCaching = false
        library = LibraryCache()
        withMutation(keyPath: \.starOverrides) { starOverrides = [:] }
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides = [:] }
        CoverArtStore.shared.configure(client: nil, cache: nil)
        UserDefaults.standard.removeObject(forKey: configKey)
        KeychainStore.delete(account: serverConfig.username)
        serverConfig = .empty
    }

    private func normalize(url rawString: String, allowInsecureHTTP: Bool = false) throws -> URL {
        var string = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        while string.hasSuffix("/") { string.removeLast() }
        let isExplicit = string.hasPrefix("http://") || string.hasPrefix("https://")
        // Default to HTTPS: credentials (password/token) travel in the query
        // string, so a schemeless host should never silently downgrade to plain HTTP.
        if !isExplicit {
            string = "https://" + string
        }
        guard let url = URL(string: string) else {
            throw SubsonicError.invalidURL
        }
        // Block plain HTTP unless the user explicitly confirmed it.
        if url.scheme == "http" && !allowInsecureHTTP {
            throw SubsonicError.insecureConnection
        }
        return url
    }

    // MARK: Playback

    func play(_ songs: [SubsonicSong], at index: Int = 0) {
        player.play(songs, startAt: index)
    }

    func play(_ song: SubsonicSong, in queue: [SubsonicSong]) {
        if let index = queue.firstIndex(where: { $0.id == song.id }) {
            player.play(queue, startAt: index)
        } else {
            player.play([song], startAt: 0)
        }
    }

    func playShuffled(_ songs: [SubsonicSong]) {
        guard !songs.isEmpty else { return }
        player.play(songs.shuffled(), startAt: 0)
    }

    /// Fetches an album's tracks and starts playing it from index 0.
    func play(_ album: SubsonicAlbum) {
        if let offline = offlineAlbumDetail(for: album.id)?.song, !offline.isEmpty {
            play(offline)
            return
        }
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: album.id))?.song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { play(songs) }
        }
    }

    /// Emulates a radio "station" for a song: fetches the full track list of
    /// the song's album and starts playing it from the current track, so it
    /// behaves like continuous similar-music radio. Falls back to just playing
    /// the song solo when it has no album.
    func playStation(from song: SubsonicSong) {
        guard let client, let albumId = song.albumId else {
            play([song])
            return
        }
        Task {
            let songs = (try? await client.getAlbum(id: albumId))?.song ?? []
            let fallback: [SubsonicSong] = [song]
            let list = songs.isEmpty ? fallback : songs
            await MainActor.run {
                if let index = list.firstIndex(where: { $0.id == song.id }) {
                    player.play(list, startAt: index)
                } else {
                    play(list)
                }
            }
        }
    }

    /// Fetches an album's tracks and queues them after the current song.
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

    /// Queues a song to play immediately after the current track.
    func playNext(_ song: SubsonicSong) {
        guard !player.queue.isEmpty else {
            player.play([song], startAt: 0)
            return
        }
        var queue = player.queue
        let insertAt = (player.currentIndex + 1) % queue.count
        queue.insert(song, at: insertAt)
        player.queue = queue
    }

    /// Appends a song to the end of the current queue ("В конец очереди").
    func playLater(_ song: SubsonicSong) {
        guard !player.queue.isEmpty else {
            player.play([song], startAt: 0)
            return
        }
        player.queue.append(song)
    }

    /// Persists the current play queue (songs + current id + position) to the
    /// server so it can be restored on the next launch.
    func saveQueueToServer() {
        guard queuePersistenceEnabled, let client,
              !player.queue.isEmpty else { return }
        Task {
            let ids = player.queue.map(\.id)
            try? await client.savePlayQueue(
                songIds: ids,
                currentId: player.currentSong?.id,
                position: player.currentTime
            )
        }
    }

    /// Loads the server-side play queue and resumes it if it's non-empty.
    func restoreQueueFromServer() async {
        guard queuePersistenceEnabled, let client else { return }
        guard let queue = try? await client.getPlayQueue(),
              let entries = queue.entry, !entries.isEmpty else { return }
        var restored = entries
        if let current = queue.current, let index = restored.firstIndex(where: { $0.id == current }) {
            let song = restored.remove(at: index)
            restored.insert(song, at: 0)
        }
        await MainActor.run {
            let wasLoaded = player.hasLoadedItem
            let previousID = player.currentSong?.id
            player.queue = restored
            player.currentIndex = 0
            // Load the restored track into AVPlayer so Play actually starts
            // after a fresh relaunch — but stay paused (no surprise audio).
            if !wasLoaded || previousID != player.currentSong?.id {
                player.startCurrent(autoPlay: false)
                player.pause()
            }
            saveQueueToServer()
        }
    }

    private func startCurrent(_ song: SubsonicSong) {
        // Cancel stale per-song work from the previously playing track.
        currentCacheTask?.cancel()
        lyricsTask?.cancel()
        scrobbleTask?.cancel()

        if let client {
            saveQueueToServer()
            lyricsTask = Task { await lyrics.load(song: song, client: client) }
            if scrobblingEnabled {
                scrobbleTask = Task { try? await client.scrobble(id: song.id, submission: false) }
            }
        }

        if startLocalOrBuffered(song) { return }
        guard let url = streamURL(for: song) else {
            player.lastError = "Этот трек не загружен для оффлайн-прослушивания."
            player.isLoading = false
            return
        }
        // Stream immediately; cache in the background so future plays are instant.
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
        await downloadToCache(song)
    }

    private func updateCachingFlag() {
        player.isCaching = activeCacheTasks.contains(player.currentSong?.id ?? "")
    }

    func cachedURL(for song: SubsonicSong) -> URL? {
        guard let cache else { return nil }
        let url = cache.fileURL(for: .streams, key: CacheManager.streamKey(songId: song.id, suffix: effectiveSuffix(for: song)))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isCached(_ song: SubsonicSong) -> Bool {
        guard cache != nil else { return false }
        guard let name = cacheFileName(for: song) else { return false }
        if !cachedStreamKeysSeeded { Task { await seedCachedStreamKeys() } }
        return cachedStreamKeys.contains(name)
    }

    private func streamKey(for song: SubsonicSong) -> String {
        CacheManager.streamKey(songId: song.id, suffix: effectiveSuffix(for: song))
    }

    /// The exact on-disk name (after sanitization) of a song's cached stream.
    private func cacheFileName(for song: SubsonicSong) -> String? {
        guard let cache else { return nil }
        return cache.fileURL(for: .streams, key: streamKey(for: song)).lastPathComponent
    }

    // MARK: Cache management

    func cacheSong(_ song: SubsonicSong) {
        guard !isCached(song) else { return }
        register(downloading: song)
        Task {
            await downloadToCache(song)
            unregisterDownload(from: [song])
        }
    }

    func cacheSongs(_ songs: [SubsonicSong]) {
        let targets = songs.filter { !isCached($0) }
        guard !targets.isEmpty else { return }
        for song in targets { register(downloading: song) }
        Task {
            for song in targets {
                if isCached(song) { continue }
                await downloadToCache(song)
            }
            unregisterDownload(from: targets)
        }
    }

    /// Downloads every track of an album for offline listening.
    func cacheAlbum(_ album: SubsonicAlbum) {
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: album.id))?.song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { self.cacheSongs(songs) }
        }
    }

    /// Downloads every track of the album the currently playing song belongs to.
    func cacheCurrentAlbum() {
        guard let currentSong = player.currentSong, let albumId = currentSong.albumId else { return }
        guard let client else { return }
        Task {
            let songs = (try? await client.getAlbum(id: albumId))?.song ?? []
            guard !songs.isEmpty else { return }
            await MainActor.run { self.cacheSongs(songs) }
        }
    }

    /// Downloads every track of a playlist for offline listening.
    func cachePlaylist(_ playlist: PlaylistSummary) {
        Task {
            let songs = await playlistSongs(for: playlist)
            guard !songs.isEmpty else { return }
            await MainActor.run { self.cacheSongs(songs) }
        }
    }

    /// Downloads every track of the currently visible playlist when one is selected.
    func cacheCurrentPlaylist() {
        guard let playlist = nav.selectedPlaylist else { return }
        cachePlaylist(playlist)
    }

    func removeFromCache(_ song: SubsonicSong) async {
        guard let cache else { return }
        let key = CacheManager.streamKey(songId: song.id, suffix: effectiveSuffix(for: song))
        await cache.removeFile(for: .streams, key: key)
        if let name = cacheFileName(for: song) {
            cachedStreamKeys.remove(name)
        }
        downloadedSongs.removeAll { $0.id == song.id }
        await removeOfflineSong(song)
    }

    /// Cancels an in-flight download (the user tapped X in the popover). The
    /// current batch write finishes, then `downloadToCache` tears down.
    func cancelDownload(_ song: SubsonicSong) {
        cancelledDownloads.insert(song.id)
    }

    /// Streams a song straight to a temp file and moves it into the stream cache,
    /// so a large lossless or transcoded file never needs to fit into memory at
    /// once. The network→file transfer runs off the main actor
    /// (`TrackDownload.streamToFile`); only progress/state updates hop back.
    func downloadToCache(_ song: SubsonicSong) async {
        guard let cache, let url = streamURL(for: song) else {
            downloadProgress.removeValue(forKey: song.id)
            return
        }
        let key = CacheManager.streamKey(songId: song.id, suffix: effectiveSuffix(for: song))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try await TrackDownload.streamToFile(
                url: url,
                destination: temp,
                isCancelled: { @Sendable [weak self] in
                    guard let self else { return true }
                    return await MainActor.run { self.cancelledDownloads.contains(song.id) }
                },
                onProgress: { @Sendable [weak self] progress in
                    Task { @MainActor in self?.downloadProgress[song.id] = progress }
                }
            )
            try await cache.moveFile(from: temp, to: .streams, key: key)
            downloadProgress.removeValue(forKey: song.id)
            cancelledDownloads.remove(song.id)
            Task { await seedCachedStreamKeys() }
            cachedStreamKeys.insert(cache.fileURL(for: .streams, key: key).lastPathComponent)
            await persistOfflineSong(song)
            prependDownloaded(song)
        } catch {
            downloadProgress.removeValue(forKey: song.id)
            cancelledDownloads.remove(song.id)
            try? FileManager.default.removeItem(at: temp)
        }
    }

    /// Track a song as currently downloading. Updates both `downloadingSongIDs`
    /// and the richer `downloadingSongs` list in start order.
    private func register(downloading song: SubsonicSong) {
        downloadingSongIDs.insert(song.id)
        if !downloadingSongs.contains(where: { $0.id == song.id }) {
            downloadingSongs.append(song)
        }
    }

    /// Clear a finished download from both the ID set and the ordered list.
    private func unregisterDownload(from songs: [SubsonicSong]) {
        let ids = Set(songs.map(\.id))
        downloadingSongIDs.subtract(ids)
        downloadingSongs.removeAll { ids.contains($0.id) }
    }

    /// Add a freshly-downloaded song to the offline list, newest first, de-duped.
    func replaceDownloadedSongs(_ songs: [SubsonicSong]) {
        downloadedSongs = songs
    }

    func prependDownloaded(_ song: SubsonicSong) {
        if downloadedSongs.contains(where: { $0.id == song.id }) { return }
        downloadedSongs.insert(song, at: 0)
    }

    // MARK: Playlist actions

    func addToPlaylist(_ songs: [SubsonicSong], playlistID: String) async {
        guard let client else { return }
        try? await client.updatePlaylist(id: playlistID, addSongIds: songs.map(\.id))
        recordRecentPlaylist(playlistID)
    }

    @discardableResult
    func createPlaylist(name: String, songs: [SubsonicSong], comment: String? = nil) async -> PlaylistDetail? {
        guard let client else { return nil }
        let created = try? await client.createPlaylist(name: name, songIds: songs.map(\.id))
        guard let id = created?.id else { return nil }
        recordRecentPlaylist(id)
        if let comment, !comment.isEmpty {
            try? await client.updatePlaylist(id: id, comment: comment)
        }
        // The new playlist must appear in the sidebar immediately; reload the
        // summary list so the "All Playlists" row reflects creation.
        await refreshPlaylists()
        return created
    }

    /// Moves a playlist to the front of the "recent" list used by the
    /// "Добавить в плейлист" submenu.
    private func recordRecentPlaylist(_ id: String) {
        var recent = recentPlaylistIDs
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recentPlaylistIDs = Array(recent.prefix(5))
    }

    /// Reloads the sidebar playlist manifest from the server. Navidrome includes
    /// a lightweight changed timestamp and song count for each playlist; those
    /// values decide whether a previously loaded full detail remains usable.
    func refreshPlaylists() async {
        guard let client else { return }
        guard let fresh = try? await client.getPlaylists() else { return }
        let summariesByID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })
        library.playlistDetails = library.playlistDetails.filter { id, detail in
            guard let summary = summariesByID[id] else { return false }
            return detail.changed == summary.changed && detail.songCount == summary.songCount
        }
        library.playlists = fresh
        library.playlistsLoaded = true
        await persistOfflinePlaylists(fresh)
    }

    /// Returns a full playlist response only while it agrees with the current
    /// lightweight playlist manifest. This makes revisiting large playlists
    /// instant without hiding server-side changes after a manifest refresh.
    func cachedPlaylistDetail(for playlist: PlaylistSummary) -> PlaylistDetail? {
        guard let detail = library.playlistDetails[playlist.id],
              detail.changed == playlist.changed,
              detail.songCount == playlist.songCount else {
            return nil
        }
        return detail
    }

    func cachePlaylistDetail(_ detail: PlaylistDetail) {
        library.playlistDetails[detail.id] = detail
    }

    func invalidatePlaylistDetail(for playlistID: String) {
        cancelPlaylistLoad(for: playlistID)
        library.playlistDetails[playlistID] = nil
    }

    /// Plays a playlist's tracks from the start, sharing the detail request
    /// with any open playlist screen instead of waiting for its rows to render.
    func play(_ playlist: PlaylistSummary) async {
        let songs = await playlistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        play(songs, at: 0)
    }

    /// Shuffles a playlist's tracks through the shared detail request.
    func playShuffled(_ playlist: PlaylistSummary) async {
        let songs = await playlistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        playShuffled(songs)
    }

    /// Queues a playlist's tracks to play immediately after the current song.
    func playNext(_ playlist: PlaylistSummary) async {
        let songs = await playlistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        var queue = player.queue
        let insertAt = (player.currentIndex + 1) % queue.count
        queue.insert(contentsOf: songs, at: insertAt)
        player.queue = queue
    }

    /// Queues a playlist's tracks at the end of the queue ("В конец очереди").
    func playLater(_ playlist: PlaylistSummary) async {
        let songs = await playlistSongs(for: playlist)
        guard !songs.isEmpty else { return }
        guard !player.queue.isEmpty else {
            play(songs, at: 0)
            return
        }
        player.queue.append(contentsOf: songs)
    }

    /// Duplicates a playlist (content + comment) under a new name.
    func duplicatePlaylist(_ playlist: PlaylistSummary) async {
        guard let client else { return }
        let songs = await playlistSongs(for: playlist)
        let newName = L10n.format("format.playlist.copyName", playlist.displayName)
        let created = try? await client.createPlaylist(name: newName, songIds: songs.map(\.id))
        if let id = created?.id, let comment = playlist.comment, !comment.isEmpty {
            try? await client.updatePlaylist(id: id, comment: comment)
        }
        await refreshPlaylists()
    }

    /// Deletes a playlist from the library.
    func deletePlaylist(_ playlist: PlaylistSummary) async {
        guard let client else { return }
        try? await client.deletePlaylist(id: playlist.id)
        if nav.selectedPlaylist?.id == playlist.id {
            nav.selected = .playlists
            nav.selectedPlaylist = nil
        }
        await refreshPlaylists()
    }

    // MARK: Stars & ratings

    /// Optimistic star overrides keyed by object id. `SubsonicSong` (and album)
    /// `starred` is an immutable snapshot, so the last toggle wins here until
    /// the next full fetch — the UI flips instantly, and a FAILED server push
    /// removes the override so the UI falls back to the server truth.
    /// Deliberately a stored property of AppState (not a nested @Observable
    /// service): every list row/menu reads it through `app.*`, and AppState
    /// mutation is the invalidation path the whole UI already observes.
    @ObservationIgnored
    private var starOverrides: [String: Bool] = [:]

    @ObservationIgnored
    private var ratingOverrides: [String: Int] = [:]

    func toggleStar<T: Starable>(_ item: T) {
        let willStar = !isStarred(item)
        // Optimistic write FIRST — before the client guard, so starring
        // works offline too (without a connection the push is simply
        // skipped and the value stays until the next full refetch).
        withMutation(keyPath: \.starOverrides) { starOverrides[item.id] = willStar }
        guard let client else { return }
        let id = item.id
        let kind = item.starKind
        // Capture client explicitly so the detached task does not keep AppState alive.
        let capturedClient = client
        Task(priority: .userInitiated) {
            do {
                switch (kind, willStar) {
                case (.song, true): try await capturedClient.star(songIds: [id])
                case (.song, false): try await capturedClient.unstar(songIds: [id])
                case (.album, true): try await capturedClient.star(albumIds: [id])
                case (.album, false): try await capturedClient.unstar(albumIds: [id])
                case (.artist, true): try await capturedClient.star(artistIds: [id])
                case (.artist, false): try await capturedClient.unstar(artistIds: [id])
                }
            } catch is CancellationError {
                return
            } catch {
                let detail = String(describing: error)
                Self.ratingLog.error("star push failed \(id, privacy: .public): \(detail, privacy: .public)")
            }
        }
    }

    /// Effective starred state: any local override wins over the snapshot.
    func isStarred<T: Starable>(_ item: T) -> Bool {
        access(keyPath: \.starOverrides)
        return starOverrides[item.id] ?? (item.starred?.isEmpty == false)
    }

    /// Effective rating (0–5) for display: the last locally-set value wins.
    func effectiveRating(for song: SubsonicSong) -> Int {
        access(keyPath: \.ratingOverrides)
        return ratingOverrides[song.id] ?? song.userRating ?? 0
    }

    /// Sets a 1–5 star rating (0 clears it), optimistic + server sync.
    /// The override is written BEFORE the client guard, so rating works
    /// offline (the push is skipped without a connection and the value
    /// stays until the next full refetch).
    func setRating(_ rating: Int, for song: SubsonicSong) {
        let clamped = min(max(rating, 0), 5)
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides[song.id] = clamped }
        guard let client else { return }
        let id = song.id
        let capturedClient = client
        Task(priority: .userInitiated) {
            do {
                try await capturedClient.setRating(clamped, id: id)
            } catch is CancellationError {
                return
            } catch {
                let detail = String(describing: error)
                Self.ratingLog.error("rating push failed \(id, privacy: .public): \(detail, privacy: .public)")
            }
        }
    }

    private nonisolated static let ratingLog = Logger(subsystem: "app.klopydrome", category: "rating")

}
// swiftlint:disable:this file_length
