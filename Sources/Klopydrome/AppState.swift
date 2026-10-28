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
    private static let maxPlaylistLoadStatesCapacity = 25
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

    var isConnecting = false
    var connectionError: String?
    var isOfflineSession = false
    var isPreparingOfflineSession = false
    var isReconnecting = false
    var isServerScanning = false
    var isFlushingOfflineMutations = false
    @ObservationIgnored var scanStatusPollingTask: Task<Void, Never>?
    var sharesManagerPresented = false
    var isBackgroundReconnecting = false
    var lastForegroundRefresh = Date()

    var cachedKeychainPassword: String?
    var didReadKeychainPassword = false
    var automaticPlaybackRecording: (song: SubsonicSong, temporaryURL: URL)?

    var isLaunching = true

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

    var shareTarget: ShareTarget?
    var inspectingSong: SubsonicSong?

    var showLyrics = true
    var queuePanelVisible = false
    var scrobblingEnabled = true

    var downloadingSongIDs: Set<String> = []

    var downloadingSongs: [SubsonicSong] = []

    var activeDownloadTasks: [DownloadTask] = []

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

    var smartPlaylists: [SmartPlaylist] = []

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
    let smartPlaylistsKey = "smartPlaylists"
    let followedKey = "followedPlaylists"
    private let queuePersistenceKey = "queuePersistenceEnabled"
    private let recentPlaylistsKey = "recentPlaylists"

    var currentCacheTask: Task<Void, Never>?
    var lyricsTask: Task<Void, Never>?
    var scrobbleTask: Task<Void, Never>?

    @ObservationIgnored
    var starOverrides: [String: Bool] = [:]

    @ObservationIgnored
    var ratingOverrides: [String: Int] = [:]

    var isConnected: Bool { client != nil }

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

    func saveSettings() {
        persist()
    }
}
