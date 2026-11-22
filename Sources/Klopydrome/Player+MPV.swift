import Foundation

extension Player {
    /// Starts the async libmpv load shared by `playMPV` (a fresh track) and by
    /// live-transcode seek restarts. `mpvLoadGeneration` guards the completion:
    /// when a newer load supersedes this one, the stale callbacks must not
    /// reset buffering state, flip play/pause or apply a leftover seek.
    func loadMPVStream(url: URL, streamRecordURL: URL?) {
        mpvLoadGeneration += 1
        let generation = mpvLoadGeneration
        Task { @MainActor in
            guard self.mpvLoadGeneration == generation else { return }
            do {
                try await mpvEngine.load(url: url, streamRecordURL: streamRecordURL)
                guard self.mpvLoadGeneration == generation else { return }
                self.isBuffering = self.isPlaying ? self.mpvEngine.isBuffering : false
                if self.mpvSeekRestartActive {
                    self.currentTime = self.heldSeekTarget ?? self.mpvStreamOffset
                    self.mpvRestartStepped = true
                }
                self.updateNowPlayingInfo()
            } catch {
                guard self.mpvLoadGeneration == generation else { return }
                self.mpvFallbackError = "mpv_init_failed"
                self.handleEngineFailure(L10n.format("format.player.failure", error.localizedDescription))
            }
        }
    }
}

// MARK: - Engine wiring

extension Player {
    func setUpMPVEngine() {
        configureMPVPlaybackCallbacks()
        configureMPVStateCallbacks()
    }

    private func configureMPVPlaybackCallbacks() {
        mpvEngine.onTrackEnded = { [weak self] in
            guard let self, self.engineKind == .mpv else { return }
            if self.isCrossfading {
                self.completeCrossfade()
            } else {
                self.onTrackEnded?()
            }
        }
        mpvEngine.onFailureCode = { [weak self] code in
            self?.mpvFallbackError = code
        }
        mpvEngine.onFailure = { [weak self] message in
            guard let self, self.engineKind == .mpv else { return }
            self.handleEngineFailure(message)
        }
        mpvEngine.onStreamRecordFinished = { [weak self] url in
            self?.onStreamRecordFinished?(url)
        }
        mpvEngine.onTimeUpdate = { [weak self] seconds in
            self?.handleMPVTimeUpdate(seconds)
        }
        mpvEngine.onDurationUpdate = { [weak self] _ in
            guard let self, self.engineKind == .mpv else { return }
            self.syncDurationFromMPVEngine()
        }
    }

    private func configureMPVStateCallbacks() {
        mpvEngine.onFileLoaded = { [weak self] in
            guard let self, self.engineKind == .mpv else { return }
            self.isLoading = false
            self.mpvSeekRestartActive = false
            self.mpvRestartStepped = false
            self.syncDurationFromMPVEngine()
            if self.isPlaying {
                self.mpvEngine.play()
            } else {
                self.mpvEngine.pause()
            }
            self.applyPendingSeekIfNeeded()
            self.updateNowPlayingInfo()
            if self.nextTrackPreloadingEnabled, let next = self.nextSongForPreloading {
                self.preloadNextMPVTrack(next)
            }
        }
        mpvEngine.onSeekableUpdate = { [weak self] seekable in
            guard let self, self.engineKind == .mpv else { return }
            if seekable {
                self.applyPendingSeekIfNeeded()
            }
        }
        mpvEngine.onBufferingUpdate = { [weak self] buffering in
            guard let self, self.engineKind == .mpv else { return }
            self.isBuffering = buffering
            if !buffering {
                self.applyPendingSeekIfNeeded()
            }
        }
    }

    private func syncDurationFromMPVEngine() {
        guard mpvStreamOffset == 0, mpvEngine.duration > 0 else { return }
        if duration != mpvEngine.duration {
            duration = mpvEngine.duration
        }
    }

    private func syncCurrentTimeAfterMPVUpdate(display: Double) {
        guard !isScrubbing else { return }
        if mpvSeekRestartActive && !mpvRestartStepped {
            return
        }
        if let held = heldSeekTarget {
            let elapsed = CFAbsoluteTimeGetCurrent() - heldSeekTargetTimestamp
            if abs(display - held) <= 1.0 || elapsed > 3.0 {
                heldSeekTarget = nil
                isSeekInFlight = false
                currentTime = display
            } else if currentTime < held {
                currentTime = held
            }
        } else {
            isSeekInFlight = false
            currentTime = display
        }
    }

    private func handleMPVTimeUpdate(_ seconds: Double) {
        guard engineKind == .mpv else { return }
        if mpvSeekRestartActive && !mpvRestartStepped {
            return
        }
        let display = seconds + mpvStreamOffset
        syncCurrentTimeAfterMPVUpdate(display: display)
        syncDurationFromMPVEngine()
        reportNowPlayingSecond(display)
        evaluateNextTrackPreload(at: display)
        evaluateCrossfade(at: display)
        if mpvSeekRestartActive && mpvRestartStepped {
            mpvSeekRestartActive = false
            mpvRestartStepped = false
            applyPendingSeekIfNeeded()
        }
    }
}
