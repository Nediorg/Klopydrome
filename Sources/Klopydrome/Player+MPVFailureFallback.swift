import Foundation
import NavidromeClient

extension Player {
    private static let maxRemoteStreamRetries = 2
    private static let remoteBufferingStallSeconds: Int = 15

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
        if recoverRemoteStreamIfPossible(at: currentTime) {
            return
        }
        resetRemoteStreamRecovery()
        resetSeekState()
        hasReportedFailure = true
        lastError = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        updateNowPlayingInfo()
    }

    func resetRemoteStreamRecovery() {
        remoteStreamRecoveryTask?.cancel()
        remoteStreamRecoveryTask = nil
        bufferingWatchdogTask?.cancel()
        bufferingWatchdogTask = nil
        remoteStreamRetryCount = 0
        remoteStreamRecoveryAnchorTime = nil
    }

    func cancelBufferingWatchdog() {
        bufferingWatchdogTask?.cancel()
        bufferingWatchdogTask = nil
    }

    func scheduleBufferingWatchdogIfNeeded() {
        guard engineKind == .mpv,
              isPlaying,
              isBuffering || isLoading,
              let url = currentSourceURL,
              !url.isFileURL,
              remoteStreamRecoveryTask == nil else {
            return
        }
        cancelBufferingWatchdog()
        let generation = mpvLoadGeneration
        let stalledPosition = currentTime
        bufferingWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.remoteBufferingStallSeconds))
            guard !Task.isCancelled,
                  let self,
                  self.mpvLoadGeneration == generation,
                  self.isPlaying,
                  self.isBuffering || self.isLoading,
                  self.currentSourceURL == url,
                  abs(self.currentTime - stalledPosition) < 0.5 else {
                return
            }
            self.bufferingWatchdogTask = nil
            if !self.recoverRemoteStreamIfPossible(at: self.currentTime) {
                self.handleEngineFailure("Playback Error".localized)
            }
        }
    }

    func noteRemotePlaybackProgress(at position: Double) {
        cancelBufferingWatchdog()
        if let anchor = remoteStreamRecoveryAnchorTime, position >= anchor + 3.0 {
            remoteStreamRetryCount = 0
            remoteStreamRecoveryAnchorTime = nil
        }
    }

    func recoverFromPrematureRemoteEOFIfNeeded() -> Bool {
        guard let url = currentSourceURL,
              !url.isFileURL,
              !isCrossfading,
              !isScrubbing,
              !isSeekInFlight else {
            return false
        }
        let expectedDuration = trackDuration
        guard expectedDuration > 15.0,
              currentTime > 1.0,
              (expectedDuration - currentTime) > 8.0 else {
            return false
        }
        return recoverRemoteStreamIfPossible(at: currentTime)
    }

    @discardableResult
    func recoverRemoteStreamIfPossible(at resumeTime: Double) -> Bool {
        guard let url = currentSourceURL,
              !url.isFileURL,
              isPlaying,
              remoteStreamRetryCount < Self.maxRemoteStreamRetries else {
            return false
        }
        cancelBufferingWatchdog()
        remoteStreamRecoveryTask?.cancel()
        remoteStreamRetryCount += 1
        remoteStreamRecoveryAnchorTime = resumeTime
        hasReportedFailure = false
        lastError = nil
        isBuffering = true

        let attempt = remoteStreamRetryCount
        let generation = mpvLoadGeneration
        let delayMilliseconds = attempt == 1 ? 400 : 1200

        remoteStreamRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled,
                  let self,
                  self.mpvLoadGeneration == generation,
                  self.isPlaying,
                  self.currentSourceURL == url else {
                return
            }
            self.remoteStreamRecoveryTask = nil
            self.reloadRemoteStream(url: url, at: resumeTime)
        }
        return true
    }

    private func reloadRemoteStream(url: URL, at resumeTime: Double) {
        if currentSourceIsRemoteTranscode, resumeTime > 1.0 {
            performTranscodeRestart(at: resumeTime)
            return
        }
        let target = resumeTime > 1.0 ? resumeTime : nil
        resetSeekState()
        currentTime = resumeTime
        pendingSeekTime = target
        heldSeekTarget = target
        if target != nil {
            heldSeekTargetTimestamp = CFAbsoluteTimeGetCurrent()
        }
        mpvStreamOffset = 0
        loadMPVStream(url: url, streamRecordURL: nil)
    }
}
