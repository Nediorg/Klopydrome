import Foundation
import NavidromeClient

// MARK: - Playback engine routing

// Playback runs on one of two engines. The MPV engine (default, selected in
// Settings) decodes every format the server can send through libmpv and seeks
// HTTP streams sample-accurately by range-requesting the exact byte offset, so
// lyric highlights stay locked to the audio. AVFoundation is the opt-out engine
// for the rare format mpv can't decode.
extension AppState {
    /// Resolves the source for the muted MPV preloader. A completed disk-cache
    /// copy is preferred; otherwise MPV begins buffering the regular stream.
    func setUpNextTrackPreloading() {
        player.automix.onNextTrackPreloadRequest = { [weak self] song in
            guard let self, self.usesMPVEngine else { return nil }
            return self.cachedURL(for: song) ?? self.streamURL(for: song)
        }
        player.automix.onCachedTrackURLRequest = { [weak self] song in
            self?.cachedURL(for: song)
        }
    }
    /// True when playback routes through the MPV engine (the default, or the
    /// user's explicit choice). When false, AVPlayer is used.
    var usesMPVEngine: Bool { serverConfig.effectivePlaybackEngine == .mpv }

    /// The suffix the chosen engine will actually decode for this song. A
    /// user-chosen transcode codec wins; the MPV engine decodes any source
    /// format natively, so only the AVPlayer engine needs the server to
    /// transcode unsupported formats to mp3.
    func effectiveSuffix(for song: SubsonicSong) -> String {
        if let format = serverConfig.format, !format.isEmpty { return format }
        if !usesMPVEngine, PlaybackFormat.needsTranscode(song.suffix) { return "mp3" }
        return (song.suffix ?? "mp3").lowercased()
    }

    /// Builds a stream URL that will actually play. Honors a user-chosen codec;
    /// with the MPV engine the original stream is requested (it decodes
    /// everything itself); only the AVPlayer engine asks the server to
    /// transcode source formats it can't decode natively.
    func streamURL(for song: SubsonicSong) -> URL? {
        guard let client else { return nil }
        // MPV probes duration from the demuxer; an estimated Content-Length
        // (bitrate*duration) for VBR transcodes can make the engine under-report
        // until fully probed. Prefer chunked without length for MPV.
        let estimate = !usesMPVEngine
        if let format = serverConfig.format, !format.isEmpty {
            return client.streamURL(
                songId: song.id,
                maxBitRate: serverConfig.maxBitRate,
                format: format,
                estimateContentLength: estimate
            )
        }
        if !usesMPVEngine, PlaybackFormat.needsTranscode(song.suffix) {
            return client.streamURL(
                songId: song.id,
                maxBitRate: serverConfig.maxBitRate,
                format: "mp3",
                estimateContentLength: estimate
            )
        }
        return client.streamURL(
            songId: song.id,
            maxBitRate: serverConfig.maxBitRate,
            estimateContentLength: estimate
        )
    }

    /// Starts playback for a song.
    /// - Returns `true` when playback has been started, `false` when nothing
    ///   loaded (no URL could be built).
    func startLocalOrBuffered(_ song: SubsonicSong) -> Bool {
        setUpNextTrackPreloading()
        // Cached copy — play it directly through the chosen engine.
        if let cached = cachedURL(for: song) {
            play(url: cached)
            return true
        }

        // Record the same MPV playback stream only while it naturally reaches
        // EOF. There is no second URLSession request, and a skipped or sought
        // track leaves no persistent partial file.
        guard let url = streamURL(for: song) else { return false }
        let streamRecordURL = beginAutomaticPlaybackCache(for: song)
        play(url: url, streamRecordURL: streamRecordURL)
        return true
    }

    /// Routes a resolved URL to the playback engine chosen in Settings: MPV
    /// for every format (default), or AVPlayer when the user opted out.
    func play(url: URL, streamRecordURL: URL? = nil) {
        if usesMPVEngine {
            player.playMPV(url, streamRecordURL: streamRecordURL)
        } else {
            player.playURL(url)
        }
    }
}
