import Foundation

extension Notification.Name {
    static let foregroundRefreshRequested = Notification.Name("ForegroundRefreshRequested")
}

extension AppState {
    func handleForegroundActivation() async {
        let now = Date()
        guard !isLaunching, now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
        lastForegroundRefresh = now
        CoverArtStore.shared.invalidateFailedKeys()
        NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
        guard !serverConfig.effectiveForceOfflineMode else { return }
        guard !isConnected, !isConnecting, !isBackgroundReconnecting,
              !serverConfig.url.isEmpty, passwordForLoginPrefill() != nil else { return }
        isBackgroundReconnecting = true
        defer { isBackgroundReconnecting = false }
        await reconnectIfPossible()
    }
}
