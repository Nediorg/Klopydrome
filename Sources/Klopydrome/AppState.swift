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
    var offlineRepository: (any OfflineRepository)?
    var currentOfflineHost: String?
    @ObservationIgnored var offlineMutationStore: OfflineMutationStore?
    @ObservationIgnored var downloadCancellationTokens: [String: OSAllocatedUnfairLock<Bool>] = [:]
    var serverConfig: ServerConfig = .empty

    var player = Player()
    let discordRichPresence = DiscordRichPresence()
    /// Latest Discord RPC connection state, surfaced in Settings so a silent
    /// "no presence in Discord" has a visible diagnosis.
    var discordConnectionStatus: DiscordRPCTransport.ConnectionStatus = .idle
    var discordSnoozeSongID: String?
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
    var isPreparingOfflineSession = false
    var isReconnecting = false
    var isServerScanning = false
    var isFlushingOfflineMutations = false
    @ObservationIgnored var scanStatusPollingTask: Task<Void, Never>?
    var sharesManagerPresented = false
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

    /// Present the "new / edit playlist" modal at the app root via inWindowModal.
    var isCreatingPlaylist = false
    var creatingPlaylistSongs: [SubsonicSong] = []
    var editingPlaylistTarget: PlaylistSummary?
    var onPlaylistModalSaved: (() -> Void)?

    /// Present the smart playlist editor modal at the app root via inWindowModal.
    var editingSmartPlaylist: SmartPlaylistEditorTarget?

    /// Opens the playlist creation / edit in-window modal at the app root.
    func openCreatePlaylist(
        songs: [SubsonicSong] = [],
        existing: PlaylistSummary? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        creatingPlaylistSongs = songs
        editingPlaylistTarget = existing
        onPlaylistModalSaved = onSaved
        isCreatingPlaylist = true
    }

    /// Opens the smart playlist rule editor in-window modal at the app root.
    func openSmartPlaylistEditor(
        playlist: SmartPlaylist? = nil,
        server: ServerSmartPlaylist? = nil
    ) {
        editingSmartPlaylist = SmartPlaylistEditorTarget(playlist: playlist, server: server)
    }

    /// Present the "share" sheet at the app root. Hoisting this here (instead of
    /// inside a context-menu component) is what makes the modal actually appear:
    /// a `.sheet` attached to a menu's transient view tree is torn down as soon
    /// as the menu closes, so the presentation never happens. The sheet is
    /// attached in `MainView` and reads this value.
    var shareTarget: ShareTarget?
    var inspectingSong: SubsonicSong?

    var showLyrics = true
    var queuePanelVisible = false
    var scrobblingEnabled = true

    /// Song ids currently being downloaded into the stream cache.
    var downloadingSongIDs: Set<String> = []

    /// Songs currently downloading, in start order, for the Downloads popover.
    /// Kept in sync with `downloadingSongIDs` (dedupes programmatic cache hits).
    var downloadingSongs: [SubsonicSong] = []

    /// Active download tasks (batches) for playlists, albums, genres, and track sets.
    var activeDownloadTasks: [DownloadTask] = []

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
        let values = downloadingSongIDs.map { downloadProgress[$0] ?? 0.0 }
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
    var cancelledDownloads: Set<String> = []
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
        configurePlayerLifecycle()
        loadPersisted()
        restorePlaybackExitPreferences()
        player.configureAutomix(
            enabled: serverConfig.effectiveAutomixEnabled,
            fadeDuration: serverConfig.effectiveAutomixFadeDuration,
            applyToAlbums: serverConfig.effectiveAutomixApplyToAlbums
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
        NetworkMonitor.shared.onConnectivityRestored = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleNetworkRestored()
            }
        }
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
            fadeDuration: config.effectiveAutomixFadeDuration,
            applyToAlbums: config.effectiveAutomixApplyToAlbums
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
        if serverConfig.effectiveForceOfflineMode {
            _ = await beginOfflineSession()
            return
        }
        guard serverConfig.url.isEmpty == false else { return }
        guard let password = passwordForLoginPrefill() else {
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни.".localized
            }
            return
        }
        do {
            try await self.connect(
                url: self.serverConfig.url,
                username: self.serverConfig.username,
                password: password,
                authMode: self.serverConfig.authMode
            )
            await self.flushOfflineMutations(promptUser: true, context: .previousSession)
        } catch is CancellationError {
            connectionError = "Нет соединения с сервером.".localized
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни.".localized
            }
        } catch {
            connectionError = error.localizedDescription
            if await beginOfflineSession() {
                connectionError = "Нет сети. Доступны сохранённые песни.".localized
            }
        }
    }

    // MARK: Connection

    private func pingWithTimeout(client: SubsonicClient) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await client.ping()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 12_000_000_000)
                throw URLError(.timedOut)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func connect(url: String, username: String, password: String,
                 authMode: AuthMode, cacheEnabled: Bool? = nil, allowInsecureHTTP: Bool = false) async throws {
        isConnecting = true
        defer { isConnecting = false }
        do {
            let base = try normalize(url: url, allowInsecureHTTP: allowInsecureHTTP)
            let config = SubsonicConfig(baseURL: base, username: username,
                                        password: password, authMode: authMode)
            let client = SubsonicClient(config: config)
            try await pingWithTimeout(client: client)

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
            availableGenres = []

            let newCache = CacheManager(rootURL: CacheManager.root(forServer: base.host ?? "default"))
            self.cache = newCache
            await restoreLibraryFromDiskCache()

            self.client = client
            self.navidrome = NavidromeAPI(baseURL: base, username: username, password: password)
            // Disk-persist the smart-playlist pool so a new session's first
            // compute can load it instead of re-crawling the whole library.
            self.smartPlaylistEngine = SmartPlaylistEngine(repo: CachedLibraryRepo(client: client, cache: newCache))
            resetCacheState()
            Task { await self.seedCachedStreamKeys() }
            serverConfig = updatedConfig
            isOfflineSession = false
            await setupOfflineRepository(host: base.host ?? "default")
            await applyCacheLimits()
            await restoreOfflineCatalog()
            self.connectionError = nil
            persist()
            persistSessionCredentials(username: username, password: password)
            CoverArtStore.shared.configure(client: client, cache: newCache,
                                           coverResolution: serverConfig.coverResolution ?? .high)
            if queuePersistenceEnabled {
                await restoreQueueFromServer()
            }
            Task(priority: .utility) { [weak self] in
                await self?.warmupLibrary()
            }
            Task { await self.checkServerScanStatus() }
        } catch {
            connectionError = error.localizedDescription
            self.client = nil
            throw error
        }
    }

    private func persistSessionCredentials(username: String, password: String) {
        if !didReadKeychainPassword || cachedKeychainPassword != password {
            try? KeychainStore.save(password: password, account: username)
        }
        cachedKeychainPassword = password
        didReadKeychainPassword = true
    }

    func disconnect() {
        discordRichPresence.clear()
        discordConnectionStatus = .idle
        discordSnoozeSongID = nil
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
        activeDownloadTasks = []
        downloadProgress = [:]
        downloadedSongs = []
        cancelledDownloads = []
        activeCacheTasks = []
        downloadCancellationTokens = [:]
        offlineRepository = nil
        currentOfflineHost = nil
        cachedStreamKeys = []
        cachedStreamKeysSeeded = false
        player.isCaching = false
        library = LibraryCache()
        withMutation(keyPath: \.starOverrides) { starOverrides = [:] }
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides = [:] }
        availableGenres = []
        stopScanStatusPolling()
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
        let localTracks = downloadedSongs.filter { ($0.albumId ?? $0.parent) == album.id }
        if !localTracks.isEmpty {
            play(localTracks)
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
    /// Starts a radio station seeded by the given song using server-side similarity.
    /// Fetches similar tracks via `getSimilarSongs2` and queues them behind the seed track.
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
                player.play(stationQueue, startAt: 0)
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
    /// server so it can be restored on the next launch. Position is saved in ms.
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

    /// Loads the server-side play queue and resumes it if it's non-empty.
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
            // Load the restored track into AVPlayer so Play actually starts
            // after a fresh relaunch — but stay paused (no surprise audio).
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

    /// The exact on-disk name (after sanitization) of a key.
    private func cacheFileName(for key: String) -> String? {
        guard let cache else { return nil }
        return cache.fileURL(for: .streams, key: key).lastPathComponent
    }

    // MARK: Cache management

    func removeFromCache(_ song: SubsonicSong) async {
        guard let cache else { return }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            let fileName = cache.fileURL(for: .streams, key: key).lastPathComponent
            if cachedStreamKeys.contains(fileName) || !cachedStreamKeysSeeded {
                await cache.removeFile(for: .streams, key: key)
                cachedStreamKeys.remove(fileName)
            }
        }
        downloadedSongs.removeAll { $0.id == song.id }
        await removeOfflineSong(song)
    }

    /// Cancels an in-flight download (the user tapped X in the popover). The
    /// current batch write finishes, then `downloadToCache` tears down.
    func cancelDownload(_ song: SubsonicSong) {
        cancelledDownloads.insert(song.id)
        downloadCancellationTokens[song.id]?.withLock { $0 = true }
    }

    /// Streams a song straight to a temp file and moves it into the stream cache,
    /// so a large lossless or transcoded file never needs to fit into memory at
    /// once. The network→file transfer runs off the main actor
    /// (`TrackDownload.streamToFile`); only progress/state updates hop back.
    func downloadToCache(_ song: SubsonicSong) async {
        guard let cache, let url = downloadStreamURL(for: song) else {
            downloadProgress.removeValue(forKey: song.id)
            return
        }
        let token = OSAllocatedUnfairLock<Bool>(initialState: cancelledDownloads.contains(song.id))
        downloadCancellationTokens[song.id] = token
        defer {
            downloadCancellationTokens.removeValue(forKey: song.id)
        }
        let key = CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            downloadProgress[song.id] = 0.0
            try await TrackDownload.streamToFile(
                url: url,
                destination: temp,
                isCancelled: { @Sendable in token.withLock { $0 } },
                onProgress: { @Sendable [weak self] progress in
                    Task { @MainActor in self?.downloadProgress[song.id] = progress }
                }
            )
            try await cache.moveFile(from: temp, to: .streams, key: key)
            downloadProgress.removeValue(forKey: song.id)
            cancelledDownloads.remove(song.id)
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
    func register(downloading song: SubsonicSong) {
        downloadingSongIDs.insert(song.id)
        if !downloadingSongs.contains(where: { $0.id == song.id }) {
            downloadingSongs.append(song)
        }
        if downloadProgress[song.id] == nil {
            downloadProgress[song.id] = 0.0
        }
    }

    /// Clear a finished download from both the ID set and the ordered list.
    func unregisterDownload(from songs: [SubsonicSong]) {
        let ids = Set(songs.map(\.id))
        downloadingSongIDs.subtract(ids)
        downloadingSongs.removeAll { ids.contains($0.id) }
        for id in ids {
            downloadProgress.removeValue(forKey: id)
        }
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
        guard confirmOfflineAction() else { return }
        if let client {
            try? await client.updatePlaylist(id: playlistID, addSongIds: songs.map(\.id))
            recordRecentPlaylist(playlistID)
            invalidatePlaylistDetail(for: playlistID)
            await refreshPlaylists()
            let isCurrent = nav.selectedPlaylist?.id == playlistID || nav.history.last?.playlistID == playlistID
            if let updated = library.playlists.first(where: { $0.id == playlistID }), isCurrent {
                await reloadPlaylist(updated)
            }
        } else {
            queueOfflineAddToPlaylist(playlistID: playlistID, songIDs: songs.map(\.id))
            recordRecentPlaylist(playlistID)
        }
    }

    @discardableResult
    func createPlaylist(
        name: String,
        songs: [SubsonicSong],
        comment: String? = nil,
        isPublic: Bool = false
    ) async -> PlaylistDetail? {
        guard confirmOfflineAction() else { return nil }
        if let client {
            let created = try? await client.createPlaylist(name: name, songIds: songs.map(\.id))
            guard let id = created?.id else { return nil }
            recordRecentPlaylist(id)
            if (comment != nil && !comment!.isEmpty) || isPublic {
                try? await client.updatePlaylist(id: id, comment: comment, isPublic: isPublic)
            }
            // The new playlist must appear in the sidebar immediately; reload the
            // summary list so the "All Playlists" row reflects creation.
            await refreshPlaylists()
            return created
        } else {
            queueOfflineCreatePlaylist(name: name, songIDs: songs.map(\.id), comment: comment, isPublic: isPublic)
            let tempID = "offline_\(UUID().uuidString)"
            let localSummary = PlaylistSummary(
                id: tempID,
                name: name,
                comment: comment,
                songCount: songs.count,
                duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
                isPublic: isPublic
            )
            library.playlists.insert(localSummary, at: 0)
            recordRecentPlaylist(tempID)
            if let offlineRepository {
                let detail = PlaylistDetail(
                    id: tempID,
                    name: name,
                    comment: comment,
                    songCount: songs.count,
                    duration: songs.reduce(0) { $0 + ($1.duration ?? 0) },
                    isPublic: isPublic,
                    entry: songs
                )
                try? await offlineRepository.savePlaylistDetail(detail)
            }
            return nil
        }
    }

    /// Moves a playlist to the front of the "recent" list used by the
    /// "Добавить в плейлист" submenu and Quick Access.
    func recordRecentPlaylist(_ id: String) {
        var recent = recentPlaylistIDs
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recentPlaylistIDs = Array(recent.prefix(10))
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
        await persistPlaylistsToDisk()
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
        Task { [weak self] in
            await self?.cache?.removeFile(for: .metadata, key: "detail_playlist_\(playlistID)")
        }
    }

    /// Duplicates a playlist (content + comment) under a new name.
    func duplicatePlaylist(_ playlist: PlaylistSummary) async {
        guard confirmOfflineAction() else { return }
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
        guard confirmOfflineAction() else { return }
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
    var starOverrides: [String: Bool] = [:]

    @ObservationIgnored
    var ratingOverrides: [String: Int] = [:]

    func toggleStar<T: Starable>(_ item: T, skipOfflineConfirm: Bool = false) {
        if !skipOfflineConfirm, !confirmOfflineAction() { return }
        let willStar = !isStarred(item)
        withMutation(keyPath: \.starOverrides) { starOverrides[item.id] = willStar }
        if willStar {
            autoCacheStarredItemIfNeeded(item)
        }
        guard let client, !isOfflineSession else {
            queueOfflineStar(id: item.id, kind: item.starKind, isStarred: willStar)
            return
        }
        pushStarToServer(client: client, id: item.id, kind: item.starKind, willStar: willStar)
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
    func setRating(_ rating: Int, for song: SubsonicSong, skipOfflineConfirm: Bool = false) {
        if !skipOfflineConfirm, !confirmOfflineAction() { return }
        let clamped = min(max(rating, 0), 5)
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides[song.id] = clamped }
        guard let client, !isOfflineSession else {
            queueOfflineRating(songID: song.id, rating: clamped)
            return
        }
        pushRatingToServer(client: client, id: song.id, rating: clamped)
    }

    private nonisolated static let ratingLog = Logger(subsystem: "app.klopydrome", category: "rating")

}
// swiftlint:disable:this file_length
