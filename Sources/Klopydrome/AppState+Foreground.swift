import Foundation

extension Notification.Name {
    /// Posted on foreground activation (debounced at the posting site):
    /// visible cover tiles re-request and errored grids retry once.
    static let foregroundRefreshRequested = Notification.Name("ForegroundRefreshRequested")
}

extension AppState {
    /// Retries what a long background typically strands: failed covers,
    /// errored grids, dropped connection. Runs on every foreground
    /// activation, debounced to 30s — the launch flow owns the first run
    /// (`isLaunching`), and manual login owns its own attempt, so both skip.
    func handleForegroundActivation() async {
        let now = Date()
        guard !isLaunching, now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
        lastForegroundRefresh = now
        CoverArtStore.shared.invalidateFailedKeys()
        NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
        guard !isConnected, !isConnecting, !isBackgroundReconnecting,
              !serverConfig.url.isEmpty, passwordForLoginPrefill() != nil else { return }
        isBackgroundReconnecting = true
        defer { isBackgroundReconnecting = false }
        await reconnectIfPossible()
    }
}
