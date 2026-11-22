import Foundation
import NavidromeClient

enum MutationFlushPolicy {
    case none
    case silent
    case prompt(AppState.PendingMutationsContext)
}

extension AppState {
    func reconnectIfPossible() async {
        defer { isLaunching = false }
        guard !serverConfig.url.isEmpty else {
            updateConnectionState(.unconfigured)
            return
        }
        if serverConfig.effectiveForceOfflineMode {
            await enterManualOfflineMode()
            return
        }

        updateConnectionState(.connecting(attempt: 1))
        await hydrateOfflineStoreIfNeeded(preserveExistingLibrary: false)

        guard let password = passwordForLoginPrefill() else {
            await enterDegradedMode(reason: .authRequired("Password required.".localized))
            return
        }

        let pathSatisfied = await NetworkMonitor.shared.waitForInitialPath(timeout: 1.5)
        if !pathSatisfied {
            await enterDegradedMode(reason: .noNetwork)
            return
        }

        await performStartupConnectAttempts(password: password)
    }

    private func performStartupConnectAttempts(password: String) async {
        let allowHTTP = resolvedAllowInsecureHTTP
        for attempt in 1...2 {
            updateConnectionState(.connecting(attempt: attempt))
            do {
                try await self.connect(
                    url: self.serverConfig.url,
                    username: self.serverConfig.username,
                    password: password,
                    authMode: self.serverConfig.authMode,
                    allowInsecureHTTP: allowHTTP,
                    mutationFlushPolicy: .prompt(.previousSession)
                )
                return
            } catch {
                let kind = TransportErrorClassifier.classify(error)
                if kind == .authFailure {
                    await enterDegradedMode(reason: .authRequired(error.localizedDescription))
                    return
                }
                if kind == .noNetwork {
                    await enterDegradedMode(reason: .noNetwork)
                    return
                }
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                let reason = healthTracker.recordProbeFailure(kind: kind, message: error.localizedDescription)
                await enterDegradedMode(reason: reason)
            }
        }
    }

    func connect(
        url: String,
        username: String,
        password: String,
        authMode: AuthMode,
        cacheEnabled: Bool? = nil,
        allowInsecureHTTP: Bool = false,
        profileName: String? = nil,
        profileID: UUID? = nil,
        mutationFlushPolicy: MutationFlushPolicy = .none
    ) async throws {
        let wasOffline = connectionState.isOfflineSession
        if !connectionState.isConnecting && !connectionState.isReconnecting {
            updateConnectionState(.connecting(attempt: 1))
        }
        do {
            let base = try normalize(url: url, allowInsecureHTTP: allowInsecureHTTP)
            let config = SubsonicConfig(
                baseURL: base,
                username: username,
                password: password,
                authMode: authMode
            )
            let probeClient = SubsonicClient(config: config)
            try await probeClient.pingProbe(timeout: 6)
            _ = try? await probeClient.getOpenSubsonicExtensions()

            await applySuccessfulConnection(
                client: probeClient,
                config: config,
                rawURL: url,
                cacheEnabled: cacheEnabled,
                allowInsecureHTTP: allowInsecureHTTP,
                profileName: profileName,
                profileID: profileID,
                wasOffline: wasOffline,
                mutationFlushPolicy: mutationFlushPolicy
            )
        } catch {
            connectionError = error.localizedDescription
            if !wasOffline {
                self.client = nil
            }
            throw error
        }
    }

    private func resolveConnectionProfile(
        rawURL: String,
        config: SubsonicConfig,
        allowInsecureHTTP: Bool,
        profileName: String?,
        profileID: UUID?
    ) -> ServerProfile {
        let storageKey = ServerProfile.makeStorageKey(url: rawURL, username: config.username)
        let resolvedName = (profileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? profileName!
            : (URL(string: rawURL)?.host ?? "Navidrome")

        var profile: ServerProfile
        if let profileID, let idx = serverProfiles.firstIndex(where: { $0.id == profileID }) {
            profile = serverProfiles[idx]
            profile.name = resolvedName
            profile.url = rawURL
            profile.username = config.username
            profile.authMode = config.authMode
            profile.allowInsecureHTTP = allowInsecureHTTP
            profile.storageKey = storageKey
            profile.lastConnectedAt = Date()
            serverProfiles[idx] = profile
        } else if let idx = serverProfiles.firstIndex(where: { $0.storageKey == storageKey }) {
            profile = serverProfiles[idx]
            profile.name = resolvedName
            profile.url = rawURL
            profile.username = config.username
            profile.authMode = config.authMode
            profile.allowInsecureHTTP = allowInsecureHTTP
            profile.lastConnectedAt = Date()
            serverProfiles[idx] = profile
        } else {
            profile = ServerProfile(
                id: profileID ?? UUID(),
                name: resolvedName,
                url: rawURL,
                username: config.username,
                authMode: config.authMode,
                allowInsecureHTTP: allowInsecureHTTP,
                storageKey: storageKey,
                lastConnectedAt: Date()
            )
            serverProfiles.append(profile)
        }
        activeProfileID = profile.id
        persistProfiles()
        return profile
    }

    private func applySuccessfulConnection(
        client: SubsonicClient,
        config: SubsonicConfig,
        rawURL: String,
        cacheEnabled: Bool?,
        allowInsecureHTTP: Bool = false,
        profileName: String? = nil,
        profileID: UUID? = nil,
        wasOffline: Bool = false,
        mutationFlushPolicy: MutationFlushPolicy = .none
    ) async {
        stopReconnectLoop()
        healthTracker.reset()

        var updatedConfig = serverConfig
        updatedConfig.url = rawURL
        updatedConfig.username = config.username
        updatedConfig.authMode = config.authMode
        updatedConfig.cacheEnabled = cacheEnabled ?? updatedConfig.cacheEnabled
        updatedConfig.allowInsecureHTTP = allowInsecureHTTP || rawURL.hasPrefix("http://")
        updatedConfig.forceOfflineMode = false

        let profile = resolveConnectionProfile(
            rawURL: rawURL,
            config: config,
            allowInsecureHTTP: updatedConfig.allowInsecureHTTP ?? false,
            profileName: profileName,
            profileID: profileID
        )

        let newCache = CacheManager(rootURL: CacheManager.root(forServer: profile.storageKey))
        let newNavidrome = NavidromeAPI(baseURL: config.baseURL, username: config.username, password: config.password)
        self.client = client
        self.navidrome = newNavidrome
        self.cache = newCache
        serverConfig = updatedConfig

        attachHealthHooks(to: client, navidrome: newNavidrome)
        updateConnectionState(.online)
        await setupOfflineRepository(host: profile.storageKey)

        switch mutationFlushPolicy {
        case .none:
            break
        case .silent:
            await flushOfflineMutations(promptUser: false)
        case .prompt(let context):
            await flushOfflineMutations(promptUser: true, context: context)
        }

        CoverArtStore.shared.configure(
            client: client,
            cache: newCache,
            coverResolution: serverConfig.coverResolution ?? .high,
            adaptiveCellularDataEnabled: serverConfig.effectiveAdaptiveCellularDataEnabled
        )
        CoverArtStore.shared.invalidateFailedKeys()

        await resetLibraryForConnection(newCache: newCache)
        await setupConnectionSession(
            client: client,
            config: config,
            profile: profile,
            newCache: newCache,
            wasOffline: wasOffline
        )
    }

    private func setupConnectionSession(
        client: SubsonicClient,
        config: SubsonicConfig,
        profile: ServerProfile,
        newCache: CacheManager,
        wasOffline: Bool = false
    ) async {
        self.smartPlaylistEngine = SmartPlaylistEngine(
            repo: CachedLibraryRepo(
                client: client,
                cache: newCache,
                localSongs: { [weak self] in self?.library.songs ?? [] }
            )
        )
        resetCacheState()
        await seedCachedStreamKeys()
        await restoreOfflineCatalog()
        await applyCacheLimits()
        self.connectionError = nil
        persist()
        persistSessionCredentials(profile: profile, password: config.password)
        if queuePersistenceEnabled {
            await restoreQueueFromServer()
        }
        if wasOffline {
            sessionGeneration += 1
        }
        warmupTask = Task(priority: .utility) { [weak self] in
            await self?.warmupLibrary()
        }
        Task { await self.checkServerScanStatus() }
        if !isProcessingDownloadQueue,
           activeDownloadTasks.contains(where: { $0.state == .waitingForNetwork || $0.state == .queued }) {
            processDownloadQueue()
        }
    }

    private func persistSessionCredentials(profile: ServerProfile, password: String) {
        if !didReadKeychainPassword || cachedKeychainPassword != password {
            try? KeychainStore.save(password: password, account: profile.keychainAccount)
            try? KeychainStore.save(password: password, account: profile.username)
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
        stopReconnectLoop()
        teardownActiveSession()
        serverConfig.url = ""
        serverConfig.username = ""
        serverConfig.serverName = ""
        serverConfig.forceOfflineMode = false
        activeProfileID = nil
        updateConnectionState(.unconfigured)
        persistProfiles()
        persist()
    }

    func normalizedServerURL(from rawString: String, allowInsecureHTTP: Bool = false) throws -> URL {
        try normalize(url: rawString, allowInsecureHTTP: allowInsecureHTTP)
    }

    private func normalize(url rawString: String, allowInsecureHTTP: Bool = false) throws -> URL {
        var string = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        while string.hasSuffix("/") { string.removeLast() }
        let isExplicit = string.hasPrefix("http://") || string.hasPrefix("https://")
        if !isExplicit {
            string = "https://" + string
        }
        guard let url = URL(string: string) else {
            throw SubsonicError.invalidURL
        }
        if url.scheme == "http" && !allowInsecureHTTP {
            throw SubsonicError.insecureConnection
        }
        return url
    }
}
