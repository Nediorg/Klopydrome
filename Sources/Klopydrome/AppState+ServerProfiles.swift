import Foundation
import NavidromeClient

extension AppState {
    func loadProfiles() {
        if let profilesData = UserDefaults.standard.data(forKey: "serverProfiles"),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: profilesData) {
            serverProfiles = decoded
        }
        if let activeUUIDString = UserDefaults.standard.string(forKey: "activeProfileID"),
           let uuid = UUID(uuidString: activeUUIDString) {
            activeProfileID = uuid
        }
        migrateLegacyServerProfileIfNeeded()
        if activeProfileID == nil, let first = serverProfiles.first {
            activeProfileID = first.id
        }
        if serverConfig.url.isEmpty, let active = activeProfile {
            serverConfig.url = active.url
            serverConfig.username = active.username
            serverConfig.authMode = active.authMode
            serverConfig.allowInsecureHTTP = active.allowInsecureHTTP
            serverConfig.serverName = active.name
        }
    }

    func persistProfiles() {
        if let data = try? JSONEncoder().encode(serverProfiles) {
            UserDefaults.standard.set(data, forKey: "serverProfiles")
        }
        if let activeProfileID {
            UserDefaults.standard.set(activeProfileID.uuidString, forKey: "activeProfileID")
        } else {
            UserDefaults.standard.removeObject(forKey: "activeProfileID")
        }
    }

    func migrateLegacyServerProfileIfNeeded() {
        let migrationKey = "serverProfilesMigrationVersion"
        let currentVersion = UserDefaults.standard.integer(forKey: migrationKey)
        guard currentVersion < 1 else { return }

        if !serverConfig.url.isEmpty && !serverConfig.username.isEmpty && serverProfiles.isEmpty {
            let legacyHost = URL(string: serverConfig.url)?.host ?? "default"
            var profile = ServerProfile(
                name: serverConfig.serverName.isEmpty ? legacyHost : serverConfig.serverName,
                url: serverConfig.url,
                username: serverConfig.username,
                authMode: serverConfig.authMode,
                allowInsecureHTTP: serverConfig.allowInsecureHTTP ?? serverConfig.url.hasPrefix("http://"),
                lastConnectedAt: Date()
            )

            let fm = FileManager.default

            let legacyCache = CacheManager.root(forServer: legacyHost)
            let newCache = CacheManager.root(forServer: profile.storageKey)
            if fm.fileExists(atPath: legacyCache.path) && !fm.fileExists(atPath: newCache.path) {
                do {
                    try fm.createDirectory(at: newCache.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: legacyCache, to: newCache)
                } catch {
                    profile.storageKey = legacyHost
                }
            }

            let legacyStoreDir = SwiftDataOfflineRepository.serverDirectory(forServer: legacyHost, create: false)
            let newStoreDir = SwiftDataOfflineRepository.serverDirectory(forServer: profile.storageKey, create: false)
            if fm.fileExists(atPath: legacyStoreDir.path) && !fm.fileExists(atPath: newStoreDir.path) {
                do {
                    try fm.createDirectory(at: newStoreDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: legacyStoreDir, to: newStoreDir)
                } catch {}
            }

            if let existingPassword = KeychainStore.password(account: profile.username) {
                try? KeychainStore.save(password: existingPassword, account: profile.keychainAccount)
            }

            if let followed = UserDefaults.standard.stringArray(forKey: followedKey) {
                UserDefaults.standard.set(followed, forKey: "\(followedKey).\(profile.storageKey)")
            }
            if let recent = UserDefaults.standard.stringArray(forKey: "recentPlaylists") {
                UserDefaults.standard.set(recent, forKey: "recentPlaylists.\(profile.storageKey)")
            }

            serverProfiles = [profile]
            activeProfileID = profile.id
            persistProfiles()
        }

        UserDefaults.standard.set(1, forKey: migrationKey)
    }

    func switchToProfile(_ profile: ServerProfile) async {
        guard activeProfileID != profile.id || client == nil else { return }
        isSwitchingServer = true
        defer { isSwitchingServer = false }

        teardownActiveSession()
        activeProfileID = profile.id
        persistProfiles()

        guard let password = passwordForProfile(profile) else {
            serverConfig.url = profile.url
            serverConfig.username = profile.username
            serverConfig.authMode = profile.authMode
            serverConfig.serverName = profile.name
            serverConfig.allowInsecureHTTP = profile.allowInsecureHTTP
            persist()
            await enterDegradedMode(reason: .authRequired("Password required.".localized))
            return
        }

        do {
            try await self.connect(
                url: profile.url,
                username: profile.username,
                password: password,
                authMode: profile.authMode,
                allowInsecureHTTP: profile.allowInsecureHTTP,
                profileName: profile.name,
                profileID: profile.id,
                mutationFlushPolicy: .prompt(.previousSession)
            )
        } catch {
            serverConfig.url = profile.url
            serverConfig.username = profile.username
            serverConfig.authMode = profile.authMode
            serverConfig.serverName = profile.name
            serverConfig.allowInsecureHTTP = profile.allowInsecureHTTP
            persist()
            let kind = TransportErrorClassifier.classify(error)
            let reason = healthTracker.recordProbeFailure(kind: kind, message: error.localizedDescription)
            await enterDegradedMode(reason: reason)
        }
    }

    func teardownActiveSession() {
        cancelActiveSessionTasks()
        resetSessionPlayback()
        resetSessionStores()
    }

    private func cancelActiveSessionTasks() {
        stopReconnectLoop()
        warmupTask?.cancel()
        warmupTask = nil
        cancelAutomaticPlaybackCache()
        cancelPlaylistLoads()
        currentCacheTask?.cancel()
        currentCacheTask = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        scrobbleTask?.cancel()
        scrobbleTask = nil
        stopScanStatusPolling()

        for token in downloadCancellationTokens.values {
            token.withLock { $0 = true }
        }
        downloadWorkerTask?.cancel()
        downloadWorkerTask = nil
        isProcessingDownloadQueue = false
        activeDownloadWorkerID = nil
    }

    private func resetSessionPlayback() {
        discordRichPresence.clear()
        discordConnectionStatus = .idle
        discordSnoozeSongID = nil
        discordAlbumArtworkURLs = [:]
        discordArtworkUnavailableAlbumIDs = []
        discordArtworkLoadingAlbumIDs = []

        player.stop()
        player.clearHistory()
        player.setQueue([])
        player.isCaching = false
    }

    private func resetSessionStores() {
        CoverArtStore.shared.clearMemoryCache()
        CoverArtStore.shared.configure(client: nil, cache: nil)
        MiniPlayerVariableBlurCache.shared.clear()
        clearInMemoryCaches()
        lyrics.reset()

        library = LibraryCache()
        playlistLoadStates = [:]
        recentPlaylistIDs = []
        availableGenres = []
        withMutation(keyPath: \.starOverrides) { starOverrides = [:] }
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides = [:] }

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
        offlineMutationStore = nil
        cachedStreamKeys = []
        cachedStreamKeysSeeded = false

        client = nil
        navidrome = nil
        cache = nil
        smartPlaylistEngine = nil
        healthTracker.reset()
        updateConnectionState(.unconfigured)
        cachedKeychainPassword = nil
        didReadKeychainPassword = false

        nav.history = []
        nav.selected = .home
        nav.selectedPlaylist = nil
        nav.searchQuery = ""
        sessionGeneration += 1
    }

    func deleteProfile(_ profile: ServerProfile) {
        KeychainStore.delete(account: profile.keychainAccount)
        serverProfiles.removeAll { $0.id == profile.id }
        persistProfiles()

        if activeProfileID == profile.id {
            if let next = serverProfiles.first {
                Task {
                    await switchToProfile(next)
                }
            } else {
                activeProfileID = nil
                persistProfiles()
                disconnect()
            }
        }
    }

    func passwordForProfile(_ profile: ServerProfile) -> String? {
        if let pw = KeychainStore.password(account: profile.keychainAccount), !pw.isEmpty {
            return pw
        }
        if let pw = KeychainStore.password(account: profile.username), !pw.isEmpty {
            return pw
        }
        return nil
    }
}
