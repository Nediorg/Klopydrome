import Foundation
import NavidromeClient

extension Notification.Name {
    static let foregroundRefreshRequested = Notification.Name("ForegroundRefreshRequested")
}

extension AppState {
    func handleForegroundActivation() async {
        guard !isLaunching else { return }
        let now = Date()

        if connectionState.isOfflineSession {
            guard canAutoReconnect else { return }
            guard now.timeIntervalSince(lastForegroundProbe) > 3 else { return }
            lastForegroundProbe = now
            _ = await triggerImmediateProbe(silent: true)
            return
        }

        guard connectionState.isOnline else { return }
        guard now.timeIntervalSince(lastForegroundRefresh) > 30 else { return }
        lastForegroundRefresh = now
        CoverArtStore.shared.invalidateFailedKeys()
        NotificationCenter.default.post(name: .foregroundRefreshRequested, object: nil)
    }
}
