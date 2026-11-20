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
                connectionError = "No network. Saved songs available.".localized
            }
            return
        }
        do {
            try await self.connect(
                url: self.serverConfig.url,
                username: self.serverConfig.username,
                password: password,
                authMode: self.serverConfig.authMode,
                allowInsecureHTTP: self.serverConfig.allowInsecureHTTP ?? self.serverConfig.url.hasPrefix("http://")
            )
            await self.flushOfflineMutations(promptUser: true, context: .previousSession)
        } catch is CancellationError {
            connectionError = "No connection to server.".localized
            if await beginOfflineSession() {
                connectionError = "No network. Saved songs available.".localized
            }
        } catch {
            connectionError = error.localizedDescription
            if await beginOfflineSession() {
                connectionError = "No network. Saved songs available.".localized
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
        allowInsecureHTTP: Bool = false,
        profileName: String? = nil,
        profileID: UUID? = nil
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
            _ = try? await client.getOpenSubsonicExtensions()

            await applySuccessfulConnection(
                client: client,
                config: config,
                rawURL: url,
                cacheEnabled: cacheEnabled,
                allowInsecureHTTP: allowInsecureHTTP,
                profileName: profileName,
                profileID: profileID
            )
        } catch {
            connectionError = error.localizedDescription
            self.client = nil
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
        profileID: UUID? = nil
    ) async {
        var updatedConfig = serverConfig
        updatedConfig.url = rawURL
        updatedConfig.username = config.username
        updatedConfig.authMode = config.authMode
        updatedConfig.cacheEnabled = cacheEnabled ?? updatedConfig.cacheEnabled
        updatedConfig.allowInsecureHTTP = allowInsecureHTTP || rawURL.hasPrefix("http://")

        let profile = resolveConnectionProfile(
            rawURL: rawURL,
            config: config,
            allowInsecureHTTP: updatedConfig.allowInsecureHTTP ?? false,
            profileName: profileName,
            profileID: profileID
        )

        let newCache = CacheManager(rootURL: CacheManager.root(forServer: profile.storageKey))
        self.client = client
        self.cache = newCache
        CoverArtStore.shared.configure(
            client: client,
            cache: newCache,
            coverResolution: serverConfig.coverResolution ?? .high,
            adaptiveCellularDataEnabled: serverConfig.effectiveAdaptiveCellularDataEnabled
        )

        await resetLibraryForConnection(newCache: newCache)
        serverConfig = updatedConfig

        await setupConnectionSession(
            client: client,
            config: config,
            profile: profile,
            newCache: newCache
        )
    }

    private func setupConnectionSession(
        client: SubsonicClient,
        config: SubsonicConfig,
        profile: ServerProfile,
        newCache: CacheManager
    ) async {
        self.navidrome = NavidromeAPI(baseURL: config.baseURL, username: config.username, password: config.password)
        self.smartPlaylistEngine = SmartPlaylistEngine(
            repo: CachedLibraryRepo(
                client: client,
                cache: newCache,
                localSongs: { [weak self] in self?.library.songs ?? [] }
            )
        )
        resetCacheState()
        await seedCachedStreamKeys()
        isOfflineSession = false
        await setupOfflineRepository(host: profile.storageKey)
        await restoreOfflineCatalog()
        await applyCacheLimits()
        self.connectionError = nil
        persist()
        persistSessionCredentials(profile: profile, password: config.password)
        if queuePersistenceEnabled {
            await restoreQueueFromServer()
        }
        warmupTask = Task(priority: .utility) { [weak self] in
            await self?.warmupLibrary()
        }
        Task { await self.checkServerScanStatus() }
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
        teardownActiveSession()
        serverConfig.url = ""
        serverConfig.username = ""
        serverConfig.serverName = ""
        activeProfileID = nil
        persistProfiles()
        persist()
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
