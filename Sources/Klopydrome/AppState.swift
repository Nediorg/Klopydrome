import Foundation
import NavidromeClient
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AppState {
    var client: SubsonicClient?
    var navidrome: NavidromeAPI?
    var cache: CacheManager?
    var offlineRepository: (any OfflineRepository)?
    var currentOfflineHost: String?
    @ObservationIgnored var offlineMutationStore: OfflineMutationStore?
    @ObservationIgnored var downloadCancellationTokens: [String: OSAllocatedUnfairLock<Bool>] = [:]
    var serverConfig: ServerConfig = .empty
    var serverProfiles: [ServerProfile] = []
    var activeProfileID: UUID?
    var isSwitchingServer = false
    var isAddingServer = false
    var sessionGeneration = 0

    var activeProfile: ServerProfile? {
        serverProfiles.first(where: { $0.id == activeProfileID })
    }

    var effectiveStorageKey: String {
        activeProfile?.storageKey ?? (serverConfig.url.isEmpty ? "default" : (URL(string: serverConfig.url)?.host ?? "default"))
    }

    var player = Player()
    let discordRichPresence = DiscordRichPresence()
    var discordConnectionStatus: DiscordRPCTransport.ConnectionStatus = .idle
    var discordSnoozeSongID: String?
    @ObservationIgnored var discordAlbumArtworkURLs: [String: URL] = [:]
    @ObservationIgnored var discordArtworkUnavailableAlbumIDs: Set<String> = []
    @ObservationIgnored var discordArtworkLoadingAlbumIDs: Set<String> = []
    var lyrics = LyricsStore()
    var nav = NavigationState()
    var library = LibraryCache()
    private static let maxPlaylistLoadStatesCapacity = 10
    @ObservationIgnored private var playlistLoadOrder: [String] = []
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

    var availableGenres: [Genre] = []

    func loadGenresIfNeeded() async {
        guard availableGenres.isEmpty, let client else { return }
        if let genres = try? await client.getGenres() {
            availableGenres = genres
        }
    }

    var smartPlaylistEngine: SmartPlaylistEngine?

    var connectionState: ConnectionState = .unconfigured
    @ObservationIgnored var healthTracker = ServerHealthTracker()
    @ObservationIgnored let circuitGate = AtomicCircuitGate()
    @ObservationIgnored var reconnectLoopTask: Task<Void, Never>?

    var connectionError: String?
    var isServerScanning = false
    var isFlushingOfflineMutations = false
    @ObservationIgnored var scanStatusPollingTask: Task<Void, Never>?
    var sharesManagerPresented = false
    var lastForegroundRefresh: Date = .distantPast
    var lastForegroundProbe: Date = .distantPast

    var cachedKeychainPassword: String?
    var didReadKeychainPassword = false
    var automaticPlaybackRecording: (song: SubsonicSong, temporaryURL: URL)?

    var isLaunching = true

    var isOnline: Bool { connectionState.isOnline }
    var allowsNetworkRequests: Bool { connectionState.isOnline && client != nil }
    var isManualOffline: Bool { connectionState.isManualOffline }
    var isAuthError: Bool { connectionState.isAuthError }
    var offlineReason: OfflineReason? { connectionState.offlineReason }
    var isConnecting: Bool { connectionState.isConnecting }
    var isReconnecting: Bool { connectionState.isReconnecting }

    var isOfflineSession: Bool {
        get { connectionState.isOfflineSession }
        set {
            if newValue {
                if !connectionState.isOfflineSession {
                    updateConnectionState(.degraded(
                        reason: .serverUnreachable(nil),
                        nextRetryAt: nil,
                        consecutiveFailures: 1
                    ))
                }
            } else if connectionState.isOfflineSession {
                updateConnectionState(client != nil ? .online : .unconfigured)
            }
        }
    }

    var isCreatingPlaylist = false
    var creatingPlaylistSongs: [SubsonicSong] = []
    var editingPlaylistTarget: PlaylistSummary?
    var onPlaylistModalSaved: (() -> Void)?

    var editingSmartPlaylist: SmartPlaylistEditorTarget?

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

    func openSmartPlaylistEditor(
        playlist: SmartPlaylist? = nil,
        server: ServerSmartPlaylist? = nil
    ) {
        editingSmartPlaylist = SmartPlaylistEditorTarget(playlist: playlist, server: server)
    }

    func toggleMiniPlayer() {
        MiniPlayerPanelController.shared.toggle(app: self)
    }

    var shareTarget: ShareTarget?
    var inspectingSong: SubsonicSong?
    var isCommandPalettePresented: Bool = false

    var showLyrics = true
    var queuePanelVisible = false
    var scrobblingEnabled: Bool = UserDefaults.standard.object(forKey: "scrobblingEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(scrobblingEnabled, forKey: "scrobblingEnabled")
        }
    }

    var downloadingSongIDs: Set<String> = []

    var downloadingSongs: [SubsonicSong] = []

    var activeDownloadTasks: [DownloadTask] = []
    var isProcessingDownloadQueue = false
    var activeDownloadWorkerID: UUID?
    var downloadWorkerTask: Task<Void, Never>?

    var downloadProgress: [String: Double] = [:]

    var downloadedSongs: [SubsonicSong] = []

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

    var hasDownloadContent: Bool {
        !activeDownloadTasks.isEmpty || !downloadingSongIDs.isEmpty || !downloadedSongs.isEmpty
    }

    var followedPlaylistIDs: Set<String> = [] {
        didSet { saveFollowedPlaylists() }
    }

    var recentPlaylistIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentPlaylistsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: recentPlaylistsKey) }
    }

    var queuePersistenceEnabled = false {
        didSet { UserDefaults.standard.set(queuePersistenceEnabled, forKey: queuePersistenceKey) }
    }

    var activeCacheTasks: Set<String> = []
    var cancelledDownloads: Set<String> = []
    var cachedStreamKeys: Set<String> = []
    var cachedStreamKeysSeeded = false
    let configKey = "serverConfig"
    let followedKey = "followedPlaylists"
    private let queuePersistenceKey = "queuePersistenceEnabled"
    private let recentPlaylistsKey = "recentPlaylists"

    var currentCacheTask: Task<Void, Never>?
    var lyricsTask: Task<Void, Never>?
    var scrobbleTask: Task<Void, Never>?
    var warmupTask: Task<Void, Never>?

    @ObservationIgnored
    var starOverrides: [String: Bool] = [:]

    @ObservationIgnored
    var ratingOverrides: [String: Int] = [:]

    var isConnected: Bool { client != nil && !connectionState.isOfflineSession }

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
        player.configureCrossfade(
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
        loadFollowedPlaylists()
        queuePersistenceEnabled = UserDefaults.standard.object(forKey: queuePersistenceKey) as? Bool ?? false
        NetworkMonitor.shared.onConnectivityRestored = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleNetworkRestored()
            }
        }
        NetworkMonitor.shared.onConnectivityLost = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleConnectivityLost()
            }
        }
        NetworkMonitor.shared.onPathChanged = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleNetworkPathChanged()
            }
        }
        setupMemoryPressureMonitoring()
        TrackFileExporter.shared.configure(environment: trackExportEnvironment)
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
        MiniPlayerVariableBlurCache.shared.clear()
        clearInMemoryCaches()
        let cacheManager = cache
        Task {
            await offlineRepository?.clearMemoryCache()
            await cacheManager?.clearInMemoryCaches()
        }
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

    private func loadPersisted() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let config = try? JSONDecoder().decode(ServerConfig.self, from: data) {
            serverConfig = config
        }
        loadProfiles()
        if !serverConfig.url.isEmpty {
            let initialCache = CacheManager(rootURL: CacheManager.root(forServer: effectiveStorageKey))
            self.cache = initialCache
            CoverArtStore.shared.configure(
                client: nil,
                cache: initialCache,
                coverResolution: serverConfig.coverResolution ?? .high,
                adaptiveCellularDataEnabled: serverConfig.effectiveAdaptiveCellularDataEnabled
            )
        }
        player.configureCrossfade(
            enabled: serverConfig.effectiveAutomixEnabled,
            fadeDuration: serverConfig.effectiveAutomixFadeDuration,
            applyToAlbums: serverConfig.effectiveAutomixApplyToAlbums
        )
        player.configureReplayGain(
            mode: serverConfig.effectiveReplayGainMode,
            preampDB: serverConfig.effectiveReplayGainPreampDB
        )
        player.configureSilenceTrim(mode: serverConfig.effectiveSilenceTrimMode)
    }

    func persist() {
        if let data = try? JSONEncoder().encode(serverConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    func saveSettings() {
        persist()
    }
}
