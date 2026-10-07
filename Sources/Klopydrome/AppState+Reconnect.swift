import Foundation
import NavidromeClient

extension AppState {
    /// Attempts to reconnect to the server without throwing away the user's active
    /// offline playback session if connection fails.
    @discardableResult
    func reconnect(silent: Bool = false) async -> Bool {
        guard !isReconnecting else { return false }
        guard !serverConfig.url.isEmpty else { return false }
        guard let password = passwordForLoginPrefill() else { return false }

        // If forced offline mode is enabled by user, do not reconnect
        if serverConfig.effectiveForceOfflineMode { return false }

        isReconnecting = true
        defer { isReconnecting = false }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.connect(
                        url: self.serverConfig.url,
                        username: self.serverConfig.username,
                        password: password,
                        authMode: self.serverConfig.authMode
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
            connectionError = nil
            isOfflineSession = false
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
        guard isOfflineSession,
              serverConfig.effectiveAutoReconnectEnabled,
              !serverConfig.effectiveForceOfflineMode,
              !isReconnecting else { return }
        _ = await reconnect(silent: true)
    }

    /// Toggles forced offline mode on or off.
    func setWorkOffline(_ offline: Bool) async {
        serverConfig.forceOfflineMode = offline
        saveSettings()
        if offline {
            isPreparingOfflineSession = true
            client = nil
            _ = await beginOfflineSession()
        } else {
            _ = await reconnect(silent: false)
        }
    }
}
