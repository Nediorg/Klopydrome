import Foundation
import NavidromeClient

extension AppState {
    @discardableResult
    func reconnect(
        silent: Bool = false,
        promptMutations: Bool = true
    ) async -> Bool {
        guard !isReconnecting, !isConnecting, !isSwitchingServer else { return false }
        guard !serverConfig.url.isEmpty else { return false }
        if serverConfig.effectiveForceOfflineMode { return false }

        guard let password = passwordForLoginPrefill() else {
            await enterDegradedMode(reason: .authRequired("Password required.".localized))
            return false
        }

        let previousReason = connectionState.offlineReason ?? .serverUnreachable(nil)
        updateConnectionState(.reconnecting(previousReason: previousReason))

        let flushPolicy: MutationFlushPolicy = promptMutations
            ? (silent ? .silent : .prompt(.offlineDisabled))
            : .none

        do {
            try await self.connect(
                url: self.serverConfig.url,
                username: self.serverConfig.username,
                password: password,
                authMode: self.serverConfig.authMode,
                allowInsecureHTTP: resolvedAllowInsecureHTTP,
                mutationFlushPolicy: flushPolicy
            )
            NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
            return true
        } catch {
            let kind = TransportErrorClassifier.classify(error)
            let reason = healthTracker.recordProbeFailure(
                kind: kind,
                message: silent ? nil : error.localizedDescription
            )
            await enterDegradedMode(reason: reason)
            return false
        }
    }

    func handleNetworkRestored() async {
        guard !serverConfig.url.isEmpty, !serverConfig.effectiveForceOfflineMode else { return }

        if connectionState.isOfflineSession {
            guard canAutoReconnect else { return }
            healthTracker.reset()
            _ = await triggerImmediateProbe(silent: true)
            return
        }

        if let client {
            do {
                try await client.pingProbe(timeout: 5)
                CoverArtStore.shared.invalidateFailedKeys()
                NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
                await flushOfflineMutations(promptUser: false)
                if !isProcessingDownloadQueue,
                   activeDownloadTasks.contains(where: { $0.state == .waitingForNetwork || $0.state == .queued }) {
                    processDownloadQueue()
                }
            } catch {
                let kind = TransportErrorClassifier.classify(error)
                let reason = healthTracker.recordProbeFailure(kind: kind, message: error.localizedDescription)
                await enterDegradedMode(reason: reason)
            }
        } else if serverConfig.effectiveAutoReconnectEnabled {
            _ = await triggerImmediateProbe(silent: true)
        }
    }

    func setWorkOffline(_ offline: Bool) async {
        if offline {
            serverConfig.forceOfflineMode = true
            saveSettings()
            await enterManualOfflineMode()
            return
        }

        let store = ensureOfflineMutationStore()
        let mutations = await store?.currentMutations() ?? OfflineMutations()
        if !mutations.isEmpty && !serverConfig.effectiveSuppressOfflinePrompts {
            let choice = promptPendingMutationsConfirmation(
                mutations: mutations,
                context: .offlineDisabled
            )
            serverConfig.forceOfflineMode = false
            saveSettings()
            switch choice {
            case .apply:
                _ = await reconnect(silent: false, promptMutations: false)
                if connectionState.isOnline {
                    await flushOfflineMutations(promptUser: false)
                }
            case .discard:
                guard await canReachCurrentServer() else {
                    await enterDegradedMode(reason: .serverUnreachable(nil))
                    return
                }
                await discardPendingMutations(mutations, store: store)
                _ = await reconnect(silent: false, promptMutations: false)
            }
        } else {
            serverConfig.forceOfflineMode = false
            saveSettings()
            _ = await reconnect(silent: false)
        }
    }

    private func canReachCurrentServer() async -> Bool {
        guard let password = passwordForLoginPrefill(),
              let base = try? normalizedServerURL(
                from: serverConfig.url,
                allowInsecureHTTP: resolvedAllowInsecureHTTP
              ) else {
            return false
        }
        let probe = SubsonicClient(config: SubsonicConfig(
            baseURL: base,
            username: serverConfig.username,
            password: password,
            authMode: serverConfig.authMode
        ))
        return (try? await probe.pingProbe(timeout: 5)) != nil
    }

    private func discardPendingMutations(_ mutations: OfflineMutations, store: OfflineMutationStore?) async {
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
    }
}
