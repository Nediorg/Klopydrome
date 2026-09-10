import Foundation

extension Player {
    /// Routes an MPV decode, output, or startup failure through a single
    /// AVFoundation retry of the same source URL. The pending URL is consumed
    /// before loading AVFoundation, so a failure there cannot retry again.
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
