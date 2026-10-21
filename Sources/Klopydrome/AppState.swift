import Foundation
import NavidromeClient
import Observation
import os
import SwiftUI

@MainActor
@Observable
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
    private static let maxPlaylistLoadStatesCapacity = 25
    @ObservationIgnored private var playlistLoadOrder: [String] = []
    /// Shared progress for detail views and playback actions loading the same
    /// playlist. SwiftUI observes snapshots while task identity stays private.
    var playlistLoadStates: [String: PlaylistLoadState] = [:] {
        didSet {
            let currentKeys = Set(playlistLoadStates.keys)
            playlistLoadOrder.removeAll { !currentKeys.contains($0) }
            for key in playlistLoadStates.keys where !playlistLoadOrder.contains(key) {
                playlistLoadOrder.append(key)
            }
            while playlistLoadOrder.count > Self.maxPlaylistLoadStatesCapacity {
                let oldest = playlistLoadOrder.removeFirst()
                playlistLoadStates.removeValue(forKey: oldest)
            }
        }
    }

    func recordPlaylistAccess(_ id: String) {
        if let index = playlistLoadOrder.firstIndex(of: id) {
            playlistLoadOrder.remove(at: index)
            playlistLoadOrder.append(id)
        }
    }
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
    var smartPlaylistEngine: SmartPlaylistEngine?

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
    var downloadedSongs: [SubsonicSong] = []

    /// Aggregate download progress (0...1) across top-level active transfers (tasks
    /// and standalone songs), or nil when nothing is downloading. Drives the progress
    /// bar under the toolbar icon.
    var overallDownloadProgress: Double? {
        var progresses: [Double] = []

        for task in activeDownloadTasks {
            progresses.append(task.progress(downloadProgress: downloadProgress))
        }

        let taskSongIDs = Set(activeDownloadTasks.flatMap { $0.songs.map(\.id) })
        let standaloneSongs = downloadingSongs.filter { !taskSongIDs.contains($0.id) }
        for song in standaloneSongs {
            progresses.append(downloadProgress[song.id] ?? 0.0)
        }

        if progresses.isEmpty {
            guard !downloadingSongIDs.isEmpty else { return nil }
            progresses = downloadingSongIDs.map { downloadProgress[$0] ?? 0.0 }
        }

        guard !progresses.isEmpty else { return nil }
        let average = progresses.reduce(0.0, +) / Double(progresses.count)
        return min(max(average, 0.0), 1.0)
    }

    /// Whether the Downloads affordance should be visible at all: any active
    /// transfer or any completed offline songs.
    var hasDownloadContent: Bool {
        !activeDownloadTasks.isEmpty || !downloadingSongIDs.isEmpty || !downloadedSongs.isEmpty
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

    var activeCacheTasks: Set<String> = []
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
    let configKey = "serverConfig"
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
    var lyricsTask: Task<Void, Never>?
    /// Scrobble-start report for the current song; cancelled when the track changes.
    var scrobbleTask: Task<Void, Never>?

    @ObservationIgnored
    var starOverrides: [String: Bool] = [:]

    @ObservationIgnored
    var ratingOverrides: [String: Int] = [:]

    var isConnected: Bool { client != nil }

    /// SwiftUI appearance matching the chosen theme.
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
        setupMemoryPressureMonitoring()
    }

    private func setupMemoryPressureMonitoring() {
        MemoryPressureMonitor.shared.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure()
            }
        }
    }

    func handleMemoryPressure() {
        CoverArtStore.shared.clearMemoryCache()
        clearInMemoryCaches()
    }

    func clearInMemoryCaches() {
        library.albumDetails = [:]
        library.artistDetails = [:]
        library.playlistDetails = [:]
        playlistLoadStates = [:]
        library.songs = []
        library.songsLoaded = false
        smartPlaylistEngine?.clearMemoryCache()
    }

    // MARK: Persistence

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            return
        }
        serverConfig = config
        if !config.url.isEmpty, let host = URL(string: config.url)?.host {
            let initialCache = CacheManager(rootURL: CacheManager.root(forServer: host))
            self.cache = initialCache
            CoverArtStore.shared.configure(
                client: nil,
                cache: initialCache,
                coverResolution: config.coverResolution ?? .high,
                adaptiveCellularDataEnabled: config.effectiveAdaptiveCellularDataEnabled
            )
        }
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

    func persist() {
        if let data = try? JSONEncoder().encode(serverConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    /// Persists the current server config (called when settings change).
    func saveSettings() {
        persist()
    }
}
