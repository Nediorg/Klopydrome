import Foundation

extension Player {
    /// Starts the async libmpv load shared by `playMPV` (a fresh track) and by
    /// live-transcode seek restarts. `mpvLoadGeneration` guards the completion:
    /// when a newer load supersedes this one, the stale callbacks must not
    /// reset buffering state, flip play/pause or apply a leftover seek.
    func loadMPVStream(url: URL, streamRecordURL: URL?) {
        mpvLoadGeneration += 1
        let generation = mpvLoadGeneration
        Task {
            do {
                _ = try await mpvEngine.load(url: url, streamRecordURL: streamRecordURL)
                await MainActor.run {
                    guard self.mpvLoadGeneration == generation else { return }
                    self.isBuffering = self.isPlaying ? self.mpvEngine.isBuffering : false
                    if self.mpvEngine.isLoaded { self.isLoading = false }
                    if self.mpvSeekRestartActive {
                        self.transcodeRestartResidual = nil
                        self.currentTime = self.heldSeekTarget ?? self.mpvStreamOffset
                        self.mpvRestartStepped = true
                    }
                    if self.isPlaying {
                        self.mpvEngine.play()
                    } else {
                        self.mpvEngine.pause()
                    }
                    self.applyPendingSeekIfNeeded()
                    self.updateNowPlayingInfo()
                }
            } catch {
                await MainActor.run {
                    guard self.mpvLoadGeneration == generation else { return }
                    self.handleEngineFailure(L10n.format("format.player.failure", error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Engine wiring

extension Player {
    func setUpMPVEngine() {
        mpvEngine.onTrackEnded = { [weak self] in
            guard let self, self.engineKind == .mpv else { return }
            self.handleMPVTrackEnded()
        }
        mpvEngine.onFailure = { [weak self] message in
            guard let self, self.engineKind == .mpv else { return }
            self.handleEngineFailure(message)
        }
        mpvEngine.onStreamRecordFinished = { [weak self] url in
            self?.onStreamRecordFinished?(url)
        }
        mpvEngine.onFileLoaded = { [weak self] in
            Task { @MainActor in
                guard let self, self.engineKind == .mpv else { return }
                self.isLoading = false
                if self.isPlaying {
                    self.mpvEngine.play()
                } else {
                    self.mpvEngine.pause()
                }
                self.applyPendingSeekIfNeeded()
                self.updateNowPlayingInfo()
            }
        }
        mpvEngine.onSeekableUpdate = { [weak self] seekable in
            Task { @MainActor in
                guard let self, self.engineKind == .mpv else { return }
                if seekable {
                    self.applyPendingSeekIfNeeded()
                }
            }
        }
        mpvEngine.onBufferingUpdate = { [weak self] buffering in
            Task { @MainActor in
                guard let self, self.engineKind == .mpv else { return }
                self.isBuffering = buffering
                if !buffering {
                    self.applyPendingSeekIfNeeded()
                }
            }
        }
        mpvEngine.onTimeUpdate = { [weak self] seconds in
            self?.handleMPVTimeUpdate(seconds)
        }
    }

    private func handleMPVTimeUpdate(_ seconds: Double) {
        guard engineKind == .mpv else { return }
        let display = seconds + mpvStreamOffset
        if !isScrubbing && !isSeekInFlight {
            if mpvSeekRestartActive && !mpvRestartStepped {
            } else if let held = heldSeekTarget {
                let elapsed = CFAbsoluteTimeGetCurrent() - heldSeekTargetTimestamp
                if abs(display - held) <= 1.0 || display >= held || elapsed > 3.0 {
                    heldSeekTarget = nil
                    currentTime = display
                } else if currentTime < held {
                    currentTime = held
                }
            } else {
                currentTime = display
            }
        }
        let newDuration = mpvEngine.duration > 0 ? mpvEngine.duration + mpvStreamOffset : 0
        if duration != newDuration {
            duration = newDuration
        }
        reportNowPlayingSecond(display)
        evaluateNextTrackPreload(at: display)
        evaluateAutomixCrossfade(at: display)
        if mpvSeekRestartActive {
            applyPendingSeekIfNeeded()
        }
    }
}
