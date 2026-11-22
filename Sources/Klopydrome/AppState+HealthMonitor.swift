import Foundation
import NavidromeClient

extension AppState {
    var resolvedAllowInsecureHTTP: Bool {
        if let profileFlag = activeProfile?.allowInsecureHTTP {
            return profileFlag
        }
        if let configFlag = serverConfig.allowInsecureHTTP {
            return configFlag
        }
        return serverConfig.url.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http://")
    }

    var canAutoReconnect: Bool {
        guard !serverConfig.url.isEmpty else { return false }
        guard serverConfig.effectiveAutoReconnectEnabled else { return false }
        guard !serverConfig.effectiveForceOfflineMode else { return false }
        switch connectionState {
        case .degraded(let reason, _, _):
            return !reason.isAuthFailure
        case .reconnecting(let previousReason):
            return !previousReason.isAuthFailure
        case .unconfigured, .manualOffline, .online, .connecting:
            return false
        }
    }

    func updateConnectionState(_ newState: ConnectionState) {
        connectionState = newState
        circuitGate.setOpen(!newState.isOnline)
    }

    func attachHealthHooks(to client: SubsonicClient, navidrome: NavidromeAPI?) {
        let gate = circuitGate
        let isOpen: @Sendable () -> Bool = { gate.isOpen }
        let onEvent: @Sendable (TransportHealthEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleTransportHealthEvent(event)
            }
        }
        client.isCircuitOpen = isOpen
        client.onHealthEvent = onEvent
        navidrome?.isCircuitOpen = isOpen
        navidrome?.onHealthEvent = onEvent
    }

    func handleTransportHealthEvent(_ event: TransportHealthEvent) {
        let decision = healthTracker.record(event, currentState: connectionState)
        switch decision {
        case .remain:
            return
        case .markOnline:
            stopReconnectLoop()
            updateConnectionState(.online)
            connectionError = nil
        case .tripDegraded(let reason):
            Task { @MainActor [weak self] in
                await self?.enterDegradedMode(reason: reason)
            }
        }
    }

    func handleConnectivityLost() async {
        guard !serverConfig.url.isEmpty else { return }
        guard connectionState != .manualOffline, connectionState != .unconfigured else { return }
        await enterDegradedMode(reason: .noNetwork)
    }

    func handleNetworkPathChanged() async {
        guard canAutoReconnect else { return }
        healthTracker.reset()
        _ = await triggerImmediateProbe(silent: true)
    }

    func enterDegradedMode(reason: OfflineReason) async {
        guard !serverConfig.url.isEmpty else {
            updateConnectionState(.unconfigured)
            return
        }
        if connectionState == .manualOffline {
            return
        }

        warmupTask?.cancel()
        warmupTask = nil
        stopScanStatusPolling()
        cancelPlaylistLoads()
        pauseDownloadWorkerForOffline()

        let failures = max(1, healthTracker.consecutiveProbeFailures)
        let retryAt: Date? = (!reason.isAuthFailure && serverConfig.effectiveAutoReconnectEnabled)
            ? Date().addingTimeInterval(ServerHealthTracker.backoffDelay(
                attempt: failures,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            ))
            : nil

        connectionError = reason.errorMessage
        updateConnectionState(.degraded(reason: reason, nextRetryAt: retryAt, consecutiveFailures: failures))

        await hydrateOfflineStoreIfNeeded(preserveExistingLibrary: !library.homeShelves.isEmpty || !library.albums.isEmpty)
        CoverArtStore.shared.configure(
            client: client,
            cache: cache,
            coverResolution: serverConfig.coverResolution ?? .high,
            adaptiveCellularDataEnabled: serverConfig.effectiveAdaptiveCellularDataEnabled
        )

        if canAutoReconnect {
            scheduleReconnectLoop()
        } else {
            stopReconnectLoop()
        }
    }

    func scheduleReconnectLoop() {
        stopReconnectLoop()
        guard canAutoReconnect else { return }
        reconnectLoopTask = Task { @MainActor [weak self] in
            await self?.runReconnectLoop()
        }
    }

    func stopReconnectLoop() {
        reconnectLoopTask?.cancel()
        reconnectLoopTask = nil
    }

    @discardableResult
    func triggerImmediateProbe(silent: Bool = true) async -> Bool {
        stopReconnectLoop()
        let recovered = await reconnect(silent: silent)
        if !recovered && canAutoReconnect {
            scheduleReconnectLoop()
        }
        return recovered
    }

    private func runReconnectLoop() async {
        var attempt = max(1, healthTracker.consecutiveProbeFailures)
        while !Task.isCancelled {
            guard canAutoReconnect else { return }
            let delay = ServerHealthTracker.backoffDelay(
                attempt: attempt,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
            if case .degraded(let reason, _, let failures) = connectionState {
                updateConnectionState(.degraded(
                    reason: reason,
                    nextRetryAt: Date().addingTimeInterval(delay),
                    consecutiveFailures: failures
                ))
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled || !canAutoReconnect { return }
            if !NetworkMonitor.shared.isPathSatisfied {
                attempt += 1
                continue
            }
            let recovered = await reconnect(silent: true)
            if recovered { return }
            attempt += 1
        }
    }

    func pauseDownloadWorkerForOffline() {
        activeDownloadWorkerID = nil
        downloadWorkerTask?.cancel()
        downloadWorkerTask = nil
        isProcessingDownloadQueue = false
        for index in activeDownloadTasks.indices where activeDownloadTasks[index].state == .active {
            activeDownloadTasks[index].state = .waitingForNetwork
        }
    }
}
