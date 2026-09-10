import Foundation
import NavidromeClient
import AVFoundation

// MARK: Seek / scrub

extension Player {
    /// Precise seek. When the current item isn't loaded yet (buffering a new
    /// stream), the target is remembered and applied as soon as the track is
    /// ready, so the request is never silently dropped.
    ///
    /// The MPV engine seeks through libmpv, which range-requests the exact byte
    /// offset, so for HTTP streams the reported position lands immediately on
    /// the target. A live transcode is the exception: it has no seekable range,
    /// so a seek crossing the buffered fragment restarts the server transcode
    /// at the target (`timeOffset`). AVPlayer's seek is asynchronous: `currentTime`
    /// is set to the target immediately and `isSeekInFlight` blocks the periodic
    /// observer from writing stale positions back while the seek is landing,
    /// otherwise the lyrics (and scrubber) would snap back to the old position
    /// for a few ticks.
    func seek(to time: Double) {
        let clamped = max(0, time)
        defer { updateNowPlayingInfo() }
        cancelAutomixCrossfade()

        if engineKind == .mpv {
            heldSeekTarget = clamped
            guard mpvEngine.isLoaded else {
                pendingSeekTime = clamped
                currentTime = clamped
                return
            }
            if mpvSeekRestartActive || seekNeedsTranscodeRestart(to: clamped) {
                setTranscodeSeek(to: clamped)
                return
            }
            currentTime = mpvEngine.seek(to: clamped)
            return
        }

        guard avPlayer.currentItem != nil else {
            pendingSeekTime = clamped
            currentTime = clamped
            return
        }
        // Remote transcodes are not seekable via AVPlayer's range requests;
        // restart the server stream at the target (timeOffset) instead.
        if mpvSeekRestartActive || avSeekNeedsTranscodeRestart(to: clamped) {
            heldSeekTarget = clamped
            setAVPTranscodeSeek(to: clamped)
            return
        }
        heldSeekTarget = clamped
        isSeekInFlight = true
        seekRequestID += 1
        let requestID = seekRequestID
        currentTime = clamped
        let pipeTarget = clamped - mpvStreamOffset
        let target = CMTime(seconds: max(0, pipeTarget), preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekRequestID == requestID else { return }
                self.isSeekInFlight = false
            }
        }
    }

    /// Applies a seek that was requested before the track finished loading.
    func applyPendingSeekIfNeeded() {
        guard let pendingSeekTime else { return }
        self.pendingSeekTime = nil
        seek(to: pendingSeekTime)
    }

    /// Begin a scrub session: the time observer stops reporting so the drag
    /// preview is the single source of truth for `currentTime`.
    func beginScrub() {
        isScrubbing = true
        heldSeekTarget = nil
    }

    /// Tune the position while scrubbing. Uses a tolerant AVPlayer seek (nearest
    /// decodable frame) and reflects it on `currentTime` immediately, so the
    /// knob follows the finger smoothly instead of jumping on release.
    func scrub(to time: Double) {
        let clamped = max(0, time)
        currentTime = clamped
        guard engineKind != .mpv else {
            // mpv seeks are cheap range requests, so while scrubbing we only
            // move the preview; `endScrub` commits the real reposition.
            if !mpvEngine.isLoaded { pendingSeekTime = clamped }
            return
        }
        guard avPlayer.currentItem != nil else {
            pendingSeekTime = clamped
            return
        }
        let pipeTarget = max(0, clamped - mpvStreamOffset)
        let target = CMTime(seconds: pipeTarget, preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
    }

    /// Commit the scrub with a precise seek and restore live tracking.
    func endScrub(at time: Double) {
        isScrubbing = false
        seek(to: time)
    }
}

// MARK: Transport

extension Player {
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        if engineKind == .mpv {
            mpvEngine.pause()
            if automix.activeCrossfade != nil { automix.preloadedMPVEngine.pause() }
        } else {
            avPlayer.pause()
        }
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resume() {
        guard let song = currentSong else { return }
        lastError = nil
        hasReportedFailure = false
        // Queue restored from the server points at a track, but nothing has
        // been loaded into the engine yet (fresh launch / restart). Resolve the
        // source first — `play()` on an empty engine is a no-op.
        if engineKind == .mpv {
            if mpvEngine.isLoaded {
                mpvEngine.play()
            } else {
                onTrackRequest?(song)
            }
            if automix.activeCrossfade != nil { automix.preloadedMPVEngine.play() }
            isPlaying = true
            updateNowPlayingInfo()
            return
        }
        if avPlayer.currentItem == nil {
            onTrackRequest?(song)
            return
        }
        avPlayer.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func stop() {
        guard hasQueue else { return }

        resetPreloadedNext()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        mpvEngine.stop()

        isPlaying = false
        isLoading = false
        isBuffering = false
        isCaching = false
        currentTime = 0
        duration = 0
        pendingSeekTime = nil
        heldSeekTarget = nil
        transcodeRestartResidual = nil
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        mpvRestartStepped = false
        updateNowPlayingInfo()
    }

    func setRepeatMode(_ mode: RepeatMode) {
        guard repeatMode != mode else { return }
        repeatMode = mode
        resetPreloadedNext()
        updateNowPlayingInfo()
    }

    func adjustVolume(by delta: Float) {
        volume = min(max(volume + delta, 0), 1)
    }

    func next() {
        guard hasQueue else { return }
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            startCurrent()
        } else if repeatMode == .all {
            currentIndex = 0
            startCurrent()
        } else {
            seek(to: 0)
            pause()
        }
    }

    func previous() {
        guard hasQueue else { return }
        if currentTime > 5 {
            seek(to: 0)
            return
        }
        if currentIndex > 0 {
            currentIndex -= 1
            startCurrent()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            startCurrent()
        } else {
            seek(to: 0)
        }
    }

    /// Called when the natural end of a track is reached.
    func trackDidFinish() {
        if engineKind == .mpv { mpvEngine.stop() }
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }
}

// MARK: Formatting

extension Player {
    func formattedCurrentTime() -> String {
        Self.format(seconds: currentTime)
    }

    func formattedDuration() -> String {
        Self.format(seconds: trackDuration)
    }

    /// Remaining playback time, rendered the Apple Music way: `-3:11`.
    /// Returns `--:--` until the duration is actually known (i.e. not 0).
    func formattedRemainingTime() -> String {
        guard trackDuration > 0 else { return "--:--" }
        let remaining = max(0, trackDuration - currentTime)
        return "-\(Self.format(seconds: remaining))"
    }

    /// Formats seconds into a timer string. Avoids `String(format:)` (a slow
    /// ObjC-bridged call) because the song table calls this once per row.
    static func format(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):" + two(minutes) + ":" + two(secs)
        }
        return "\(minutes):" + two(secs)
    }

    @inline(__always) static func two(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
