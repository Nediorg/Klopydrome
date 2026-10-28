import Foundation

struct MPVFailureFallback {
    private var pendingURL: URL?

    mutating func arm(for url: URL?) {
        pendingURL = url
    }

    mutating func takeURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    mutating func clear() {
        pendingURL = nil
    }
}

extension Player {
    func handleEngineFailure(_ message: String) {
        guard engineKind == .mpv, !hasReportedFailure else { return }
        if let fallbackURL = mpvFailureFallback.takeURL() {
            mpvEngine.stop()
            resetPreloadedNext()
            automix.currentSourceURL = nil
            mpvStreamOffset = 0
            mpvSeekRestartActive = false
            mpvRestartStepped = false
            heldSeekTarget = nil
            transcodeRestartResidual = nil
            isBuffering = false
            isLoading = false
            lastError = nil
            hasReportedFailure = false
            playURL(fallbackURL)
            return
        }
        hasReportedFailure = true
        lastError = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    func armMPVFailureFallback(for url: URL?) {
        mpvFailureFallback.arm(for: url)
    }
}
