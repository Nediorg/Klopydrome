import Foundation

/// The MPV (`libmpv`) path of `Player`, kept in an extension so the main
/// player type stays well under the lint size limits. Active whenever the
/// user's engine setting selects MPV (the default) — every format, since
/// mpv decodes natively and seeks HTTP streams sample-accurately.
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
                    // Don't seed `duration` with the stale value returned by
                    // `load` (previous track's duration or 0). `trackDuration`
                    // falls back to `currentSong.duration` until mpv reports the
                    // real `duration` via the property-change event.
                    self.isBuffering = self.isPlaying ? self.mpvEngine.isBuffering : false
                    if self.mpvEngine.isLoaded { self.isLoading = false }
                    if self.mpvSeekRestartActive {
                        // A transcode seek restart: the fresh pipe is already
                        // streaming from the target offset on the server.
                        // Do not issue an in-pipe seek onto an unbuffered live stream;
                        // update currentTime and let playback resume smoothly.
                        self.transcodeRestartResidual = nil
                        self.currentTime = self.heldSeekTarget ?? self.mpvStreamOffset
                        self.mpvRestartStepped = true
                    }
                    // Respect a pause issued while the async load was in flight
                    // (the launch-time queue restore loads the track but must
                    // stay paused — no surprise audio on startup).
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
    /// Wires the MPV engine's callbacks into the player. Called once from
    /// `init()`; the engine itself is shared for every track.
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
            Task { @MainActor in
                self?.handleMPVTimeUpdate(seconds)
            }
        }
    }

    private func handleMPVTimeUpdate(_ seconds: Double) {
        guard engineKind == .mpv else { return }
        let display = seconds + mpvStreamOffset
        if !isScrubbing && !isSeekInFlight {
            if mpvSeekRestartActive && !mpvRestartStepped {
                // keep currentTime at the held target
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
        duration = mpvEngine.duration > 0 ? mpvEngine.duration + mpvStreamOffset : 0
        reportNowPlayingSecond(display)
        evaluateNextTrackPreload(at: display)
        evaluateAutomixCrossfade(at: display)
        if mpvSeekRestartActive {
            applyPendingSeekIfNeeded()
        }
    }
}
