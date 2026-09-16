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
    /// Minimum distance for a seek on a live transcode to request a fresh
    /// stream from the server. Navidrome serves transcodes as live chunked
    /// pipes with integer second timeOffset resolution. Small sub-second
    /// differences are left alone to avoid flushing the demuxer buffer.
    private var transcodedSeekCushion: Double { 1.0 }

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

    /// A seek on a live remote transcode always requires a server restart when
    /// the target moves by at least the cushion distance, because live pipes
    /// lack HTTP range headers and cannot be range-seeked.
    func seekNeedsTranscodeRestart(to target: Double) -> Bool {
        currentSourceIsRemoteTranscode &&
            abs(target - mpvRealPosition) >= transcodedSeekCushion
    }

    func avSeekNeedsTranscodeRestart(to target: Double) -> Bool {
        currentSourceIsRemoteTranscode &&
            abs(target - avRealPosition) >= transcodedSeekCushion
    }

    func setAVPTranscodeSeek(to target: Double) {
        guard avPlayer.currentItem != nil else {
            pendingSeekTime = target
            currentTime = target
            return
        }
        let crossesBuffer = abs(target - avRealPosition) >= transcodedSeekCushion
        guard !crossesBuffer else {
            if mpvSeekRestartActive && isBuffering {
                pendingSeekTime = target
                return
            }
            performAVPTranscodeRestart(at: target)
            return
        }
    }

    private func performAVPTranscodeRestart(at target: Double) {
        guard let url = automix.currentSourceURL,
              let offsetURL = Self.transcodedSeekURL(from: url, at: target) else { return }
        let offset = Double(max(0, Int(target)))
        mpvStreamOffset = offset
        mpvSeekRestartActive = true
        mpvRestartStepped = false
        transcodeRestartResidual = nil
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

    /// Commits a seek on a live transcode. Seeks that move by at least 1s
    /// trigger a clean server restart via `timeOffset`. While a restarted pipe
    /// is buffering, further seeks coalesce into `pendingSeekTime` (last wins)
    /// and apply once settled, so rapid scrubs never overlap restarts.
    func setTranscodeSeek(to target: Double) {
        guard mpvEngine.isLoaded else {
            pendingSeekTime = target
            currentTime = target
            return
        }
        let crossesBuffer = abs(target - mpvRealPosition) >= transcodedSeekCushion
        guard !crossesBuffer else {
            if mpvSeekRestartActive && mpvEngine.isBuffering {
                pendingSeekTime = target
                return
            }
            performTranscodeRestart(at: target)
            return
        }
    }

    /// Reloads the current stream via the Subsonic `timeOffset` parameter, so
    /// the server opens a fresh transcode starting at `target`. Audio is
    /// stopped first: while the old pipe runs, libmpv keeps reporting its
    /// pre-restart position, which fights the painted target. Playback is
    /// resumed by the load completion only once the fresh pipe is loaded.
    /// `mpvStreamOffset` is recorded before the load so clock math stays
    /// consistent.
    func performTranscodeRestart(at target: Double) {
        guard let url = automix.currentSourceURL,
              let offsetURL = Self.transcodedSeekURL(from: url, at: target) else { return }
        let offset = Double(max(0, Int(target)))
        mpvStreamOffset = offset
        mpvSeekRestartActive = true
        mpvRestartStepped = false
        transcodeRestartResidual = nil
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
