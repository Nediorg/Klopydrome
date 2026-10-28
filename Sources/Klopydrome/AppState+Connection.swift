import Foundation
import SwiftUI
import NavidromeClient

extension AppState {
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

    // MARK: - Connection Lifecycle

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

    func connect(
        url: String,
        username: String,
        password: String,
        authMode: AuthMode,
        cacheEnabled: Bool? = nil,
        allowInsecureHTTP: Bool = false
    ) async throws {
        isConnecting = true
        defer { isConnecting = false }
        do {
            let base = try normalize(url: url, allowInsecureHTTP: allowInsecureHTTP)
            let config = SubsonicConfig(
                baseURL: base,
                username: username,
                password: password,
                authMode: authMode
            )
            let client = SubsonicClient(config: config)
            try await pingWithTimeout(client: client)

            var updatedConfig = serverConfig
            updatedConfig.url = url
            updatedConfig.username = username
            updatedConfig.authMode = authMode
            updatedConfig.cacheEnabled = cacheEnabled ?? updatedConfig.cacheEnabled

            let newCache = CacheManager(rootURL: CacheManager.root(forServer: base.host ?? "default"))
            await resetLibraryForConnection(newCache: newCache)

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
            CoverArtStore.shared.configure(
                client: client,
                cache: newCache,
                coverResolution: serverConfig.coverResolution ?? .high
            )
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

    private func resetLibraryForConnection(newCache: CacheManager) async {
        cancelPlaylistLoads()
        library = LibraryCache()
        withMutation(keyPath: \.starOverrides) { starOverrides = [:] }
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides = [:] }
        availableGenres = []
        self.cache = newCache
        await restoreLibraryFromDiskCache()
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
}
