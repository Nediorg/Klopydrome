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
                    self.isBuffering = false
                    self.isLoading = false
                    if self.mpvSeekRestartActive {
                        // A transcode seek restart: audio stopped at the old
                        // position, so step the fractional remainder onto the
                        // target while still frozen, then let playback resume
                        // exactly where the user asked.
                        var residual: Double = 0
                        if let pending = self.transcodeRestartResidual {
                            self.transcodeRestartResidual = nil
                            residual = pending
                            self.mpvEngine.seek(to: pending)
                        }
                        self.currentTime = self.mpvStreamOffset + residual
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
        mpvEngine.onTimeUpdate = { [weak self] seconds in
            Task { @MainActor in
                guard let self, self.engineKind == .mpv else { return }
                // Resolve the pipe-relative engine clock against the absolute
                // stream start (0 for normal loads, the restart offset after a
                // live-transcode seek), so timers/lyrics/scrubber and the
                // preload/crossfade triggers always see real track seconds.
                let display = seconds + self.mpvStreamOffset
                if !self.isScrubbing && !self.isSeekInFlight {
                    // Before a restart's fresh pipe is loaded and stepped, a
                    // tick is either the old pipe's pre-restart position or the
                    // newborn pipe's 0 — offset by the new start they read as a
                    // far-forward target and would release the held clock.
                    // Ignore them; only the stepped pipe's clock is real.
                    if self.mpvSeekRestartActive && !self.mpvRestartStepped {
                        // keep currentTime at the held target
                    } else if let held = self.heldSeekTarget {
                        // Hold a seeked target on screen until the real position
                        // catches up, so a fresh load or a restart can't snap the
                        // timeline back to 0 (or the pre-seek spot).
                        if display >= held - 0.25 {
                            self.heldSeekTarget = nil
                            self.currentTime = display
                        } else if self.currentTime < held {
                            self.currentTime = held
                        }
                    } else {
                        self.currentTime = display
                    }
                }
                self.duration = self.mpvEngine.duration > 0
                    ? self.mpvEngine.duration + self.mpvStreamOffset
                    : 0
                self.reportNowPlayingSecond(display)
                self.evaluateNextTrackPreload(at: display)
                self.evaluateAutomixCrossfade(at: display)
                // Rapid seeks during a transcode-restart buffering are coalesced
                // into `pendingSeekTime`; apply them once the pipe is playing
                // again (isBuffering clears on the first time-pos tick).
                if self.mpvSeekRestartActive {
                    self.applyPendingSeekIfNeeded()
                }
            }
        }
    }
}
