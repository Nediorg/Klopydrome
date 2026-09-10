import Foundation
import AVFoundation
import NavidromeClient
import Libmpv

/// Audio playback engine backed by libmpv (via MPVKit).
///
/// mpv owns decoding, sample-rate conversion, gapless concatenation and
/// HTTP-range seeking, so it plays local files and streamed Subsonic tracks
/// without the hand-rolled `AVAudioPlayerNode` feeder that stuttered under
/// main-thread or network pressure. The engine is fully headless: `vo=null`
/// and CoreAudio output require no view. The SwiftUI/lyric clock is driven by
/// mpv's `time-pos` property (observed through the libmpv event loop), and
/// track-end is detected via `MPV_EVENT_END_FILE` with reason `EOF`.
@MainActor
final class MPVPlaybackEngine {
    // The decoder/player is owned outright; its lifetime matches the engine.
    private var mpv: OpaquePointer?

    /// Owns the libmpv event loop and runs it entirely off the main actor.
    private let pump = EventPump()

    // Transport state.
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var isEnded = false
    private(set) var isBuffering = false

    /// Whether the current source supports range-style seeking. False for a
    /// server transcode still in flight (no Content-Length, no accept-ranges);
    /// mpv flips it once the stream is a seekable file (cached transcode,
    /// original). This is the ground truth for transcode-seek decisions — far
    /// more reliable than guessing from the reported duration, which mpv sets
    /// to 0/inf/NaN for unknown-length pipes.
    private(set) var isSeekable = false

    /// Track metadata. `duration` is filled by the `duration` property event
    /// once mpv has demuxed the source (fast for local, after headers for HTTP).
    private(set) var duration: Double = 0
    private(set) var sampleRate: Double = 44_100
    private(set) var channels = 2

    /// Desired linear output gain (0…1), shared with the AVFoundation path.
    var volume: Float = 1.0 {
        didSet { applyVolume() }
    }

    var replayGainMode: ReplayGainMode = .off {
        didSet { applyReplayGain() }
    }

    var replayGainPreampDB: Float = AutomixLoudness.crossfadeHeadroomDB {
        didSet { applyReplayGain() }
    }

    var silenceTrimMode: SilenceTrimMode = .off {
        didSet { applyAudioFilter() }
    }

    var onTrackEnded: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?

    private var streamRecordURL: URL?
    private var streamRecordIsContiguous = false

    /// Cached playback position (seconds), updated from mpv's `time-pos`
    /// property events on the background event queue. Read on the main actor
    /// via `currentTime` / forwarded through `onTimeUpdate`.
    private var currentTimeValue: Double = 0


    // MARK: - libmpv lifecycle

    /// Destroys the libmpv context when the wrapper goes away. Engines are
    /// replaced on track handoff (`promotePreloadedMPVTrack`); without this the
    /// old context's core thread kept running and fired its wakeup callback
    /// into a freed `EventPump` (use-after-free, crash in `dispatch_async`).
    deinit {
        guard let mpv else { return }
        // Stop new wakeups first, then drain the pump: after this, no code
        // path can touch the context while it is being torn down.
        mpv_set_wakeup_callback(mpv, nil, nil)
        pump.finish()
        mpv_terminate_destroy(mpv)
    }

    private func ensureMpv() throws {
        guard mpv == nil else { return }
        guard let handle = mpv_create() else {
            throw NSError(domain: "MPVPlaybackEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create mpv context"])
        }
        mpv = handle
        pump.mpv = handle
        pump.engine = self
        mpv_set_option_string(mpv, "vo", "null")
        mpv_set_option_string(mpv, "ao", "coreaudio")
        // macOS 27 can crash libmpv's CoreAudio hotplug callback when its
        // default planar float output sees a device change (including a monitor
        // with audio connecting or disconnecting). Interleaved float preserves
        // the signal precision while avoiding that affected CoreAudio path.
        mpv_set_option_string(mpv, "audio-format", "float")
        // Klopydrome owns MPNowPlayingInfoCenter and MPRemoteCommandCenter.
        // Letting MPV register macOS media keys lets it publish a URL-derived
        // fallback title and replace the app's artwork in Control Center.
        mpv_set_option_string(mpv, "input-media-keys", "no")
        mpv_set_option_string(mpv, "gapless", "yes")
        mpv_set_option_string(mpv, "force-seekable", "yes")
        mpv_set_option_string(mpv, "terminal", "no")
        mpv_set_option_string(mpv, "msg-level", "all=warn")
        for option in AutomixLoudness.mpvOptions(
            replayGainMode: replayGainMode,
            preampDB: replayGainPreampDB,
            silenceTrimMode: silenceTrimMode
        ) {
            mpv_set_option_string(mpv, option.name, option.value)
        }
        mpv_set_option_string(mpv, "pause", "yes")

        // Bound mpv's demuxer/network caches: its defaults are sized for video
        // (up to ~150MB of buffered demuxed data), which is far more than an
        // audio stream needs — the app also caches streams to disk itself, so
        // mpv only needs a few seconds of lookahead for gapless playback.
        mpv_set_option_string(mpv, "demuxer-max-bytes", "16MiB")
        mpv_set_option_string(mpv, "demuxer-max-back-bytes", "8MiB")
        mpv_set_option_string(mpv, "cache-secs", "10")

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "seekable", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(mpv, MPVPlaybackEngine.wakeup, Unmanaged.passUnretained(pump).toOpaque())

        if mpv_initialize(mpv) < 0 {
            mpv_set_wakeup_callback(mpv, nil, nil)
            pump.finish()
            mpv_terminate_destroy(mpv)
            mpv = nil
            throw NSError(domain: "MPVPlaybackEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to initialize mpv"])
        }
        // Preferences are restored before libmpv has a context, so the earlier
        // `volume` didSet cannot reach mpv. Apply the retained value now.
        applyVolume()
    }
    /// C-convention callback mpv invokes when events are pending. It bounces
    /// straight to the `EventPump`'s own serial queue, where the loop runs
    /// entirely off the main actor.
    private static let wakeup: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx else { return }
        let pump = Unmanaged<EventPump>.fromOpaque(ctx).takeUnretainedValue()
        pump.queue.async { pump.readEvents() }
    }

    // MARK: - Event pump callbacks

    /// Called on the main actor by `EventPump` (throttled to ~10 Hz for
    /// `time-pos`). All libmpv parsing already happened off-thread, so this is
    /// only the cheap UI-state assignment — no main-thread busy loop.
    @MainActor func applyTimePos(_ pos: Double) {
        currentTimeValue = pos
        isBuffering = false
        onTimeUpdate?(pos)
    }

    @MainActor func setDuration(_ d: Double) {
        // mpv reports 0/inf/NaN for an unknown-length pipe (a transcode still
        // in flight). Keep only a usable finite value.
        duration = d.isFinite && d > 0 ? d : 0
    }

    @MainActor func setSeekable(_ value: Bool) {
        isSeekable = value
    }

    @MainActor func handleTrackEnded() {
        // mpv can emit MPV_EVENT_END_FILE/EOF on HTTP streams before the
        // track is actually finished (e.g. demuxer buffer drains or a
        // transient network hiccup). If we are still far from the known
        // duration, treat it as a spurious EOF and resume instead of
        // advancing to the next track.
        if duration > 0, currentTimeValue + 3 < duration {
            isEnded = false
            isBuffering = false
            play()
            return
        }
        let completedRecord = streamRecordIsContiguous ? streamRecordURL : nil
        clearStreamRecord(removeFile: completedRecord == nil)
        if let completedRecord { onStreamRecordFinished?(completedRecord) }
        if !isEnded {
            isEnded = true
            isPlaying = false
            onTrackEnded?()
        }
    }

    @MainActor func handleTrackFailure(errorCode: Int32) {
        guard !isEnded else { return }
        clearStreamRecord(removeFile: true)
        isLoaded = false
        isEnded = true
        isPlaying = false
        isBuffering = false
        onFailure?(L10n.format("format.mpv.openFailure", Int(errorCode)))
    }

    // MARK: - Loading
    func load(url: URL, streamRecordURL: URL? = nil) async throws -> FormatInfo {
        try ensureMpv()
        configureStreamRecord(streamRecordURL)
        isLoaded = true
        isEnded = false
        isBuffering = true
        isSeekable = false
        currentTimeValue = 0
        duration = 0
        mpvCommand(["loadfile", url.absoluteString, "replace"])
        return FormatInfo(duration: duration, sampleRate: sampleRate, channels: channels)
    }

    // MARK: - Transport

    func play() {
        guard isLoaded, !isPlaying else { return }
        isPlaying = true
        setPaused(false)
        isBuffering = false
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        isBuffering = false
        setPaused(true)
    }

    func stop() {
        clearStreamRecord(removeFile: true)
        isPlaying = false
        isEnded = false
        isBuffering = false
        mpvCommand(["stop"])
        currentTimeValue = 0
    }

    /// Seeks to `seconds` (absolute). mpv performs the seek; the landed position
    /// is reflected by `currentTime` via `time-pos` events. Returns the clamped
    /// request so the UI can update immediately.
    @discardableResult
    func seek(to seconds: Double) -> Double {
        // A seek can create discontinuities in stream-record output, so only a
        // naturally completed, contiguous playback is eligible for auto-cache.
        streamRecordIsContiguous = false
        let clamped = max(0, seconds)
        isBuffering = true
        mpvCommand(["seek", String(clamped), "absolute"])
        return clamped
    }

    // MARK: - Time

    /// Last known playback position (seconds). Driven by mpv's `time-pos`
    /// property events; `onTimeUpdate` forwards it to the player on the main
    /// actor, so this never performs a synchronous libmpv call on the UI thread.
    var currentTime: Double { currentTimeValue }

    func cancelStreamRecord() {
        clearStreamRecord(removeFile: true)
    }

    private func configureStreamRecord(_ url: URL?) {
        clearStreamRecord(removeFile: true)
        streamRecordURL = url
        streamRecordIsContiguous = url != nil
        guard let mpv else { return }
        mpv_set_property_string(mpv, "stream-record", url?.path ?? "")
    }

    private func clearStreamRecord(removeFile: Bool) {
        let url = streamRecordURL
        streamRecordURL = nil
        streamRecordIsContiguous = false
        guard let mpv else { return }
        mpv_set_property_string(mpv, "stream-record", "")
        if removeFile, let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - mpv command/property helpers
    private func mpvCommand(_ parts: [String]) {
        guard let mpv else { return }
        var args: [UnsafePointer<CChar>?] = []
        for part in parts {
            args.append(strdup(part).map { UnsafePointer($0) })
        }
        args.append(nil)
        _ = args.withUnsafeMutableBufferPointer { buffer in
            mpv_command(mpv, buffer.baseAddress)
        }
        for arg in args.dropLast() {
            if let arg { free(UnsafeMutablePointer(mutating: arg)) }
        }
    }

    private func setPaused(_ paused: Bool) {
        guard let mpv else { return }
        var flag: Int32 = paused ? 1 : 0
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
    }

    private func applyReplayGain() {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "replaygain", replayGainMode.mpvValue)
        let preamp = AutomixLoudness.formatDecibels(replayGainPreampDB)
        mpv_set_property_string(mpv, "replaygain-preamp", preamp)
        mpv_set_property_string(mpv, "replaygain-fallback", preamp)
    }

    private func applyAudioFilter() {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "af", silenceTrimMode.mpvAudioFilterOption() ?? "")
    }

    private func applyVolume() {
        guard let mpv else { return }
        let control = PlaybackVolume.mpvControl(forOutputGain: volume)
        var scaled = Double(control) * 100
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &scaled)
    }
}

/// Drains the libmpv event loop on a dedicated background serial queue,
/// fully off the main actor. It parses events and forwards only the resulting
/// state to `MPVPlaybackEngine` on the main actor via `DispatchQueue.main.async`,
/// so even a high-frequency `time-pos` stream (or a momentary `NULL` return from
/// `mpv_wait_event`) can never saturate the UI thread.
/// EventPump's mutable event state is confined to `queue`: configuration is
/// complete before libmpv can invoke its callback, and `finish()` synchronously
/// clears it on that same queue before the libmpv context is destroyed.
private final class EventPump: @unchecked Sendable {
    weak var engine: MPVPlaybackEngine?
    var mpv: OpaquePointer?
    let queue = DispatchQueue(label: "mpv.event")
    var lastTimeUpdate: CFAbsoluteTime = 0

    func readEvents() {
        let handle = mpv
        guard let handle else { return }
        while true {
            // Non-blocking drain: timeout 0 returns MPV_EVENT_NONE immediately
            // when nothing is queued, so the loop exits as soon as the queue
            // is empty. A bounded wait would keep looping forever while the
            // engine plays (time-pos arrives faster than any timeout), which
            // starved `finish()` and hung the main actor on engine swap.
            guard let event = mpv_wait_event(handle, 0) else { break }
            if event.pointee.event_id == MPV_EVENT_NONE {
                break
            }
            dispatch(event)
            // Teardown may have cleared the handle while we were dispatching;
            // never call mpv again after that.
            guard mpv == handle else { break }
        }
    }

    /// Stops consuming events. Called from the engine's deinit; must return
    /// before `mpv_terminate_destroy` runs so no `mpv_wait_event` survives the
    /// context's lifetime.
    func finish() {
        queue.sync {
            mpv = nil
            engine = nil
        }
    }

    private func dispatch(_ event: UnsafeMutablePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)
        case MPV_EVENT_END_FILE:
            handleEndFile(event)
        default:
            break
        }
    }

    private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let propPtr = event.pointee.data?.assumingMemoryBound(to: mpv_event_property.self) else { return }
        let prop = propPtr.pointee
        let name = String(cString: prop.name)
        if name == "time-pos", let dptr = prop.data?.assumingMemoryBound(to: Double.self) {
            let pos = dptr.pointee
            // Throttle forwarded ticks to ~4 Hz. The engine still samples at
            // mpv's native rate; only the main-actor hop is rate-limited so
            // @Observable invalidations don't fire 10–20 times/sec.
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastTimeUpdate >= 0.25 else { return }
            lastTimeUpdate = now
            DispatchQueue.main.async { [weak self] in
                self?.engine?.applyTimePos(pos)
            }
        } else if name == "duration", let dptr = prop.data?.assumingMemoryBound(to: Double.self) {
            let d = dptr.pointee
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setDuration(d)
            }
        } else if name == "seekable", let fptr = prop.data?.assumingMemoryBound(to: Int32.self) {
            let flag = fptr.pointee != 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setSeekable(flag)
            }
        }
    }

    private func handleEndFile(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let endPtr = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self) else { return }
        switch endPtr.pointee.reason {
        case MPV_END_FILE_REASON_EOF:
            DispatchQueue.main.async { [weak self] in
                self?.engine?.handleTrackEnded()
            }
        case MPV_END_FILE_REASON_ERROR:
            let errorCode = endPtr.pointee.error
            DispatchQueue.main.async { [weak self] in
                self?.engine?.handleTrackFailure(errorCode: errorCode)
            }
        default:
            break
        }
    }
}

/// Format metadata returned by `load`. Only `duration` is consumed by `Player`.
struct FormatInfo {
    let duration: Double
    let sampleRate: Double
    let channels: Int
}
