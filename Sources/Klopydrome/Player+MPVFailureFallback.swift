import Foundation

extension Player {
    func handleEngineFailure(_ message: String) {
        guard engineKind == .mpv, !hasReportedFailure else { return }
        if let currentSong, currentSourceURL?.isFileURL == true {
            currentSourceURL = nil
            onLocalFilePlaybackFailed?(currentSong)
            return
        }
        if mpvSeekRestartActive,
           currentSourceIsRemoteTranscode,
           mpvFallbackError == "nothing_to_play" {
            mpvFallbackError = nil
            resetSeekState()
            isBuffering = false
            isLoading = false
            hasReportedFailure = false
            lastError = nil
            onTrackEnded?()
            return
        }
        resetSeekState()
        hasReportedFailure = true
        lastError = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        updateNowPlayingInfo()
    }
}
