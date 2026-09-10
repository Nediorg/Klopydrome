import AVFoundation
import Foundation

/// Seeking through a freshly transcoded Subsonic stream.
///
/// Navidrome serves an uncached transcode as an unknown-length pipe with no
/// HTTP range support (`Accept-Ranges: none`), so libmpv can only move within
/// the audio it has already downloaded. A seek crossing the buffered fragment
/// in either direction therefore needs the server to open a fresh transcode
/// at the target, which the Subsonic `timeOffset` parameter requests. Once
/// the server has the transcode cached it resumes serving it as a normal
/// seekable file and this fallback never fires.
///
/// Every restarted pipe starts its own clock at 0, so `mpvStreamOffset` records
/// the absolute position the pipe began at. All position math in the player
/// (timers, lyrics, scrubber, preload/crossfade triggers) uses the sum of the
/// engine's pipe-relative time and that offset; otherwise the display would
/// snap back to 0 and run N seconds behind the real track position.
extension Player {
    /// How many seconds of audio libmpv keeps buffered around the playback
    /// position (matches the MPV engine's `cache-secs=10`). A seek crossing
    /// that range on a live transcode cannot be read from the buffer.
    private var transcodedSeekCushion: Double { 10 }

    /// True when the current source is a remote transcode (its URL carries a
    /// server `format` parameter instead of being a local file).
    var currentSourceIsRemoteTranscode: Bool {
        Self.isRemoteTranscodeStreamURL(automix.currentSourceURL)
    }

    /// The actual playback position in the current MPV pipe, converted to
    /// absolute track seconds. Used as the anchor for transcode-seek decisions
    /// — unlike `currentTime`, it is never the scrub-preview or an optimistic
    /// paint, so chasing an unbuffered region is not mistaken for an in-buffer
    /// nudge.
    var mpvRealPosition: Double {
        mpvEngine.currentTime + mpvStreamOffset
    }

    var avRealPosition: Double {
        let base = avPlayer.currentTime().seconds
        let pipePos = base.isFinite ? base : 0
        return pipePos + mpvStreamOffset
    }

    var avSeekableTimeRangesEmpty: Bool {
        avPlayer.currentItem?.seekableTimeRanges.isEmpty ?? true
    }

    /// First-time decision: a seek needs a server restart when the current
    /// source is a remote transcode whose pipe mpv cannot range-seek (a live
    /// transcode has no Content-Length and no accept-ranges, so libmpv reports
    /// it non-seekable and can only move within what it already downloaded).
    /// mpv's `duration` for such a pipe is meaningless (0/inf/NaN), so the
    /// decision rests on `seekable`, not on the reported duration. Once a
    /// restart has happened (`mpvSeekRestartActive`) the pipe is known
    /// non-seekable and the decision is made regardless of any duration the
    /// engine reports later.
    func seekNeedsTranscodeRestart(to target: Double) -> Bool {
        currentSourceIsRemoteTranscode &&
            !mpvSeekRestartActive &&
            !mpvEngine.isSeekable &&
            abs(target - mpvRealPosition) > transcodedSeekCushion
    }

    func avSeekNeedsTranscodeRestart(to target: Double) -> Bool {
        guard currentSourceIsRemoteTranscode else { return false }
        // AVPlayer exposes seekability via seekableTimeRanges; a live
        // transcode has empty ranges or an indefinite duration.
        let item = avPlayer.currentItem
        let seekableEmpty = item?.seekableTimeRanges.isEmpty ?? true
        let duration = item?.duration
        let indefinite = duration == nil || duration!.isIndefinite || (duration?.seconds ?? 0) <= 0
        let notSeekable = seekableEmpty || indefinite
        return notSeekable && abs(target - avRealPosition) > transcodedSeekCushion
    }

    func setAVPTranscodeSeek(to target: Double) {
        guard avPlayer.currentItem != nil else {
            pendingSeekTime = target
            currentTime = target
            return
        }
        let crossesBuffer = abs(target - avRealPosition) > transcodedSeekCushion
        guard !crossesBuffer else {
            if mpvSeekRestartActive && isBuffering {
                pendingSeekTime = target
                return
            }
            performAVPTranscodeRestart(at: target)
            return
        }
        if mpvSeekRestartActive && isBuffering {
            pendingSeekTime = target
            return
        }
        // In-buffer nudge: try a normal AVPlayer seek; if the pipe is not
        // seekable it will be caught on the next seek as a cross-buffer jump.
        isSeekInFlight = true
        seekRequestID += 1
        let requestID = seekRequestID
        currentTime = target
        heldSeekTarget = target
        let cmTarget = CMTime(seconds: target - mpvStreamOffset, preferredTimescale: 600)
        avPlayer.seek(to: cmTarget, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekRequestID == requestID else { return }
                self.isSeekInFlight = false
            }
        }
    }

    private func performAVPTranscodeRestart(at target: Double) {
        guard let url = automix.currentSourceURL,
              let offsetURL = Self.transcodedSeekURL(from: url, at: target) else { return }
        let offset = Double(max(0, Int(target)))
        mpvStreamOffset = offset
        mpvSeekRestartActive = true
        mpvRestartStepped = false
        transcodeRestartResidual = target - offset
        duration = 0
        currentTime = target
        heldSeekTarget = target
        isBuffering = true
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        // Give the engine a moment to settle before loading the new pipe.
        let item = AVPlayerItem(url: offsetURL)
        observeItemStatus(item)
        avPlayer.replaceCurrentItem(with: item)
        // AVPlayer's new pipe starts at 0; display offset keeps the scrubber
        // at the absolute position. Mark stepped immediately — the hold logic
        // will keep the target until the new pipe's time catches up.
        mpvRestartStepped = true
        if isPlaying {
            avPlayer.play()
        }
    }

    /// Commits a seek on a live transcode, measuring distance from the real
    /// engine position. Small seeks are served by libmpv's local buffer; only
    /// a target past the buffered range restarts the server stream. While a
    /// restarted pipe is still buffering, further seeks are coalesced into
    /// `pendingSeekTime` (last wins) and applied once a time tick observes the
    /// pipe settled, so rapid scrubs never overlap two server restarts.
    func setTranscodeSeek(to target: Double) {
        guard mpvEngine.isLoaded else {
            pendingSeekTime = target
            currentTime = target
            return
        }
        let crossesBuffer = abs(target - mpvRealPosition) > transcodedSeekCushion
        guard !crossesBuffer else {
            if mpvSeekRestartActive && mpvEngine.isBuffering {
                pendingSeekTime = target
                return
            }
            performTranscodeRestart(at: target)
            return
        }
        // In-buffer nudge. During a restart's buffering window even a small
        // seek is deferred until the pipe is actually playing again.
        if mpvSeekRestartActive && mpvEngine.isBuffering {
            pendingSeekTime = target
            return
        }
        let pipeTarget = target - mpvStreamOffset
        currentTime = mpvEngine.seek(to: max(0, pipeTarget))
    }

    /// Reloads the current stream via the Subsonic `timeOffset` parameter, so
    /// the server opens a fresh transcode starting at `target`. Audio is
    /// stopped first: while the old pipe runs, libmpv keeps reporting its
    /// pre-restart position, which fights the painted target. Playback is
    /// resumed by the load completion only once the fresh pipe is loaded and
    /// stepped onto the target. `mpvStreamOffset` is recorded before the load
    /// so the clock math stays consistent, and `pendingSeekTime` is left
    /// alone — a seek issued while the new pipe buffers is re-decided after it
    /// settles.
    private func performTranscodeRestart(at target: Double) {
        guard let url = automix.currentSourceURL,
              let offsetURL = Self.transcodedSeekURL(from: url, at: target) else { return }
        let offset = Double(max(0, Int(target)))
        mpvStreamOffset = offset
        mpvSeekRestartActive = true
        mpvRestartStepped = false
        transcodeRestartResidual = target - offset
        duration = 0
        currentTime = target
        heldSeekTarget = target
        isBuffering = true
        mpvEngine.pause()
        loadMPVStream(url: offsetURL, streamRecordURL: nil)
    }

    /// Rebuilds a Subsonic stream URL with the `timeOffset` query value set to
    /// `target` (seconds, truncated). Other parameters are preserved.
    nonisolated static func transcodedSeekURL(from url: URL, at target: Double) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let offset = max(0, Int(target))
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "timeOffset" }
        items.append(URLQueryItem(name: "timeOffset", value: String(offset)))
        components.queryItems = items
        return components.url
    }

    /// Reports whether `url` is a remotely transcoded stream: a non-file URL
    /// carrying a non-empty Subsonic `format` query value.
    nonisolated static func isRemoteTranscodeStreamURL(_ url: URL?) -> Bool {
        guard let url, !url.isFileURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains {
            $0.name == "format" && !($0.value ?? "").isEmpty
        } ?? false
    }
}
