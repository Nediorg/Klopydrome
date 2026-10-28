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
    private var mpv: OpaquePointer?

    private let pump = EventPump()

    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var isEnded = false
    private(set) var isBuffering = false

    private(set) var isSeekable = false

    private(set) var duration: Double = 0
    private(set) var sampleRate: Double = 44_100
    private(set) var channels = 2

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
    var onBufferingUpdate: ((Bool) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?
    var onFileLoaded: (() -> Void)?
    var onSeekableUpdate: ((Bool) -> Void)?

    private var isPausedForCache = false
    private var streamRecordURL: URL?
    private var streamRecordIsContiguous = false

    private var currentTimeValue: Double = 0

    // MARK: - libmpv lifecycle

    /// Destroys the libmpv context when the wrapper goes away. Engines are
    /// replaced on track handoff (`promotePreloadedMPVTrack`); without this the
    /// old context's core thread kept running and fired its wakeup callback
    /// into a freed `EventPump` (use-after-free, crash in `dispatch_async`).
    deinit {
        if let url = streamRecordURL {
            try? FileManager.default.removeItem(at: url)
        }
        guard let mpv else { return }
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
        mpv_set_option_string(mpv, "audio-format", "float")
        mpv_set_option_string(mpv, "input-media-keys", "no")
        mpv_set_option_string(mpv, "gapless", "yes")
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

        mpv_set_option_string(mpv, "demuxer-max-bytes", "16MiB")
        mpv_set_option_string(mpv, "demuxer-max-back-bytes", "8MiB")
        mpv_set_option_string(mpv, "cache-secs", "10")

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "seekable", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_set_wakeup_callback(mpv, MPVPlaybackEngine.wakeup, Unmanaged.passUnretained(pump).toOpaque())

        if mpv_initialize(mpv) < 0 {
            mpv_set_wakeup_callback(mpv, nil, nil)
            pump.finish()
            mpv_terminate_destroy(mpv)
            mpv = nil
            throw NSError(domain: "MPVPlaybackEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to initialize mpv"])
        }
        applyVolume()
    }
    private static let wakeup: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx else { return }
        let pump = Unmanaged<EventPump>.fromOpaque(ctx).takeUnretainedValue()
        pump.queue.async { pump.readEvents() }
    }

    @MainActor func updateBuffering(_ value: Bool) {
        guard isBuffering != value else { return }
        isBuffering = value
        onBufferingUpdate?(value)
    }

    @MainActor func setPausedForCache(_ value: Bool) {
        isPausedForCache = value
        updateBuffering(value)
    }

    @MainActor func applyTimePos(_ pos: Double) {
        currentTimeValue = pos
        updateBuffering(isPausedForCache)
        onTimeUpdate?(pos)
    }

    @MainActor func setDuration(_ d: Double) {
        duration = d.isFinite && d > 0 ? d : 0
    }

    @MainActor func setSeekable(_ value: Bool) {
        guard isSeekable != value else { return }
        isSeekable = value
        onSeekableUpdate?(value)
    }

    @MainActor func handleFileLoaded() {
        isLoaded = true
        isEnded = false
        onFileLoaded?()
    }

    @MainActor func handleTrackEnded() {
        if duration > 0, currentTimeValue + 3 < duration {
            isEnded = false
            isPausedForCache = false
            updateBuffering(false)
            play()
            return
        }
        let completedRecord = streamRecordIsContiguous ? streamRecordURL : nil
        clearStreamRecord(removeFile: completedRecord == nil)
        if let completedRecord { onStreamRecordFinished?(completedRecord) }
        if !isEnded {
            isEnded = true
            isPlaying = false
            isPausedForCache = false
            updateBuffering(false)
            onTrackEnded?()
        }
    }

    @MainActor func handleTrackFailure(errorCode: Int32) {
        guard !isEnded else { return }
        clearStreamRecord(removeFile: true)
        isLoaded = false
        isEnded = true
        isPlaying = false
        isPausedForCache = false
        updateBuffering(false)
        onFailure?(L10n.format("format.mpv.openFailure", Int(errorCode)))
    }

    func load(url: URL, streamRecordURL: URL? = nil) async throws -> FormatInfo {
        try ensureMpv()
        configureStreamRecord(streamRecordURL)
        isLoaded = false
        isEnded = false
        updateBuffering(true)
        isSeekable = false
        currentTimeValue = 0
        duration = 0
        setPaused(!isPlaying)
        mpvCommand(["loadfile", url.absoluteString, "replace"])
        return FormatInfo(duration: duration, sampleRate: sampleRate, channels: channels)
    }

    // MARK: - Transport

    func play() {
        isPlaying = true
        setPaused(false)
        updateBuffering(isPausedForCache)
    }

    func pause() {
        isPlaying = false
        updateBuffering(false)
        setPaused(true)
    }

    func stop() {
        clearStreamRecord(removeFile: true)
        isLoaded = false
        isPlaying = false
        isEnded = false
        isPausedForCache = false
        updateBuffering(false)
        mpvCommand(["stop"])
        currentTimeValue = 0
    }

    #if DEBUG
    func setIsLoadedForTesting(_ loaded: Bool) {
        isLoaded = loaded
    }
    #endif

    @discardableResult
    func seek(to seconds: Double) -> Bool {
        guard isLoaded else { return false }
        streamRecordIsContiguous = false
        let clamped = max(0, seconds)
        if isPlaying {
            updateBuffering(true)
        }
        let status = mpvCommand(["seek", String(clamped), "absolute"])
        if status >= 0 {
            currentTimeValue = clamped
            return true
        }
        return false
    }

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
    @discardableResult
    private func mpvCommand(_ parts: [String]) -> Int32 {
        guard let mpv else { return -1 }
        var args: [UnsafePointer<CChar>?] = []
        for part in parts {
            args.append(strdup(part).map { UnsafePointer($0) })
        }
        args.append(nil)
        let status = args.withUnsafeMutableBufferPointer { buffer in
            mpv_command(mpv, buffer.baseAddress)
        }
        for arg in args.dropLast() {
            if let arg { free(UnsafeMutablePointer(mutating: arg)) }
        }
        return status
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
            guard let event = mpv_wait_event(handle, 0) else { break }
            if event.pointee.event_id == MPV_EVENT_NONE {
                break
            }
            dispatch(event)
            guard mpv == handle else { break }
        }
    }

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
        case MPV_EVENT_FILE_LOADED:
            DispatchQueue.main.async { [weak self] in
                self?.engine?.handleFileLoaded()
            }
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
        } else if name == "paused-for-cache", let fptr = prop.data?.assumingMemoryBound(to: Int32.self) {
            let flag = fptr.pointee != 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setPausedForCache(flag)
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

struct FormatInfo {
    let duration: Double
    let sampleRate: Double
    let channels: Int
}
