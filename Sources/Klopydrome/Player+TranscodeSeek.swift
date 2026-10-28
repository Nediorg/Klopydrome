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
    private var transcodedSeekCushion: Double { 1.0 }

    var currentSourceIsRemoteTranscode: Bool {
        Self.isRemoteTranscodeStreamURL(automix.currentSourceURL)
    }

    var mpvRealPosition: Double {
        mpvEngine.currentTime + mpvStreamOffset
    }

    var avRealPosition: Double {
        guard let avPlayer else { return mpvStreamOffset }
        let base = avPlayer.currentTime().seconds
        let pipePos = base.isFinite ? base : 0
        return pipePos + mpvStreamOffset
    }

    var avSeekableTimeRangesEmpty: Bool {
        avPlayer?.currentItem?.seekableTimeRanges.isEmpty ?? true
    }

    func seekNeedsTranscodeRestart(to target: Double) -> Bool {
        currentSourceIsRemoteTranscode &&
            abs(target - mpvRealPosition) >= transcodedSeekCushion
    }

    func avSeekNeedsTranscodeRestart(to target: Double) -> Bool {
        currentSourceIsRemoteTranscode &&
            abs(target - avRealPosition) >= transcodedSeekCushion
    }

    func setAVPTranscodeSeek(to target: Double) {
        guard let avPlayer, avPlayer.currentItem != nil else {
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
        let player = ensureAVPlayer()
        let offset = Double(max(0, Int(target)))
        mpvStreamOffset = offset
        mpvSeekRestartActive = true
        mpvRestartStepped = false
        transcodeRestartResidual = nil
        duration = 0
        currentTime = target
        heldSeekTarget = target
        isBuffering = true
        player.pause()
        player.replaceCurrentItem(with: nil)
        let item = AVPlayerItem(url: offsetURL)
        observeItemStatus(item)
        player.replaceCurrentItem(with: item)
        mpvRestartStepped = true
        if isPlaying {
            player.play()
        }
    }

    func setTranscodeSeek(to target: Double) {
        guard mpvEngine.isLoaded else {
            pendingSeekTime = target
            currentTime = target
            return
        }
        let crossesBuffer = abs(target - mpvRealPosition) >= transcodedSeekCushion
        guard !crossesBuffer else {
            if mpvEngine.isBuffering {
                pendingSeekTime = target
                currentTime = target
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

    nonisolated static func transcodedSeekURL(from url: URL, at target: Double) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let offset = max(0, Int(target))
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "timeOffset" }
        items.append(URLQueryItem(name: "timeOffset", value: String(offset)))
        components.queryItems = items
        return components.url
    }

    nonisolated static func isRemoteTranscodeStreamURL(_ url: URL?) -> Bool {
        guard let url, !url.isFileURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains {
            $0.name == "format" && !($0.value ?? "").isEmpty
        } ?? false
    }
}
