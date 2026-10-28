import Foundation
import NavidromeClient

extension AppState {
    /// Attempts to reconnect to the server without throwing away the user's active
    /// offline playback session if connection fails.
    @discardableResult
    func reconnect(
        silent: Bool = false,
        promptMutations: Bool = true
    ) async -> Bool {
        guard !isReconnecting else { return false }
        guard !serverConfig.url.isEmpty else { return false }
        guard let password = passwordForLoginPrefill() else { return false }

        // If forced offline mode is enabled by user, do not reconnect
        if serverConfig.effectiveForceOfflineMode { return false }

        isReconnecting = true
        defer { isReconnecting = false }

        do {
            try await self.connect(
                url: self.serverConfig.url,
                username: self.serverConfig.username,
                password: password,
                authMode: self.serverConfig.authMode
            )
            connectionError = nil
            isOfflineSession = false
            if promptMutations {
                await flushOfflineMutations(promptUser: !silent, context: .offlineDisabled)
            }
            return true
        } catch {
            if !silent {
                connectionError = error.localizedDescription
            }
            // Keep offline session alive so user can continue listening
            return false
        }
    }

    /// Invoked when NetworkMonitor detects connectivity restored.
    func handleNetworkRestored() async {
        if isOfflineSession {
            guard serverConfig.effectiveAutoReconnectEnabled,
                  !serverConfig.effectiveForceOfflineMode,
                  !isReconnecting else { return }
            _ = await reconnect(silent: true)
        } else {
            // Online session restored: verify connection, trigger view refresh, flush queued mutations
            if let client {
                try? await client.ping()
                CoverArtStore.shared.invalidateFailedKeys()
                NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
                await flushOfflineMutations(promptUser: false)
            }
        }
    }

    /// Toggles forced offline mode on or off.
    func setWorkOffline(_ offline: Bool) async {
        if offline {
            serverConfig.forceOfflineMode = true
            saveSettings()
            isPreparingOfflineSession = true
            client = nil
            _ = await beginOfflineSession()
        } else {
            let store = ensureOfflineMutationStore()
            let mutations = await store?.currentMutations() ?? OfflineMutations()
            if !mutations.isEmpty && !serverConfig.effectiveSuppressOfflinePrompts {
                let choice = promptPendingMutationsConfirmation(
                    mutations: mutations,
                    context: .offlineDisabled
                )
                switch choice {
                case .apply:
                    serverConfig.forceOfflineMode = false
                    saveSettings()
                    let connected = await reconnect(silent: false, promptMutations: false)
                    if connected {
                        await flushOfflineMutations(promptUser: false)
                    }
                case .discard:
                    await store?.clear()
                    withMutation(keyPath: \.starOverrides) { starOverrides.removeAll() }
                    withMutation(keyPath: \.ratingOverrides) { ratingOverrides.removeAll() }
                    for (id, star) in mutations.stars where star.kind == .playlist {
                        if star.isStarred {
                            followedPlaylistIDs.remove(id)
                        } else {
                            followedPlaylistIDs.insert(id)
                        }
                    }
                    serverConfig.forceOfflineMode = false
                    saveSettings()
                    _ = await reconnect(silent: false, promptMutations: false)
                }
            } else {
                serverConfig.forceOfflineMode = false
                saveSettings()
                _ = await reconnect(silent: false)
            }
        }
    }
}
