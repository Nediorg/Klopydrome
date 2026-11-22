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
    var mpv: OpaquePointer?

    private let pump = EventPump()

    var isLoaded = false
    var isPlaying = false
    var isEnded = false
    var isBuffering = false
    var hasAppendedTrack = false
    var appendedURL: URL?
    var didAdvanceToAppendedTrack = false

    var isSeekable = false
    var duration: Double = 0

    var activeEntryID: Int64?
    var appendedEntryID: Int64?

    var volume: Float = 1.0 {
        didSet { applyVolume() }
    }

    var replayGainMode: ReplayGainMode = .off {
        didSet { applyReplayGain() }
    }

    var replayGainPreampDB: Float = AutomixLoudness.defaultPreampDB {
        didSet { applyReplayGain() }
    }

    var silenceTrimMode: SilenceTrimMode = .off {
        didSet { applyAudioFilter() }
    }

    var onTrackEnded: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onFailureCode: ((String) -> Void)?
    var onTimeUpdate: ((Double) -> Void)?
    var onDurationUpdate: ((Double) -> Void)?
    var onBufferingUpdate: ((Bool) -> Void)?
    var onStreamRecordFinished: ((URL) -> Void)?
    var onFileLoaded: (() -> Void)?
    var onSeekableUpdate: ((Bool) -> Void)?

    var isPausedForCache = false
    var streamRecordURL: URL?
    var streamRecordIsContiguous = false

    var currentTimeValue: Double = 0
    private var hasRetainedWakeupPump = false

    deinit {
        if let url = streamRecordURL {
            try? FileManager.default.removeItem(at: url)
        }
        guard let mpv else { return }
        mpv_set_wakeup_callback(mpv, nil, nil)
        pump.finish()
        mpv_terminate_destroy(mpv)
        if hasRetainedWakeupPump {
            hasRetainedWakeupPump = false
            Unmanaged.passUnretained(pump).release()
        }
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
        mpv_set_option_string(mpv, "gapless-audio", "yes")
        mpv_set_option_string(mpv, "prefetch-playlist", "yes")
        mpv_set_option_string(mpv, "terminal", "no")
        mpv_set_option_string(mpv, "msg-level", "all=warn")
        for option in AutomixLoudness.mpvOptions(
            replayGainMode: replayGainMode,
            preampDB: replayGainPreampDB,
            silenceTrimMode: silenceTrimMode
        ) where option.name != "af" {
            mpv_set_option_string(mpv, option.name, option.value)
        }
        mpv_set_option_string(mpv, "pause", "yes")

        mpv_set_option_string(mpv, "demuxer-max-bytes", "16MiB")
        mpv_set_option_string(mpv, "demuxer-max-back-bytes", "8MiB")
        mpv_set_option_string(mpv, "cache-secs", "10")

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "seekable", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        let pumpPtr = Unmanaged.passRetained(pump).toOpaque()
        hasRetainedWakeupPump = true
        mpv_set_wakeup_callback(mpv, MPVPlaybackEngine.wakeup, pumpPtr)

        if mpv_initialize(mpv) < 0 {
            mpv_set_wakeup_callback(mpv, nil, nil)
            pump.finish()
            mpv_terminate_destroy(mpv)
            mpv = nil
            if hasRetainedWakeupPump {
                hasRetainedWakeupPump = false
                Unmanaged.passUnretained(pump).release()
            }
            throw NSError(domain: "MPVPlaybackEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to initialize mpv"])
        }
        applyVolume()
        applyAudioFilter()
    }
    private static let wakeup: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
        guard let ctx else { return }
        let pump = Unmanaged<EventPump>.fromOpaque(ctx).takeUnretainedValue()
        pump.queue.async { pump.readEvents() }
    }

    func load(url: URL, streamRecordURL: URL? = nil) async throws {
        try ensureMpv()
        configureStreamRecord(streamRecordURL)
        activeEntryID = nil
        appendedEntryID = nil
        hasAppendedTrack = false
        appendedURL = nil
        didAdvanceToAppendedTrack = false
        isLoaded = false
        isEnded = false
        updateBuffering(true)
        isSeekable = false
        currentTimeValue = 0
        duration = 0
        setPaused(!isPlaying)
        activeEntryID = mpvCommandEntryID(["loadfile", url.absoluteString, "replace"])
    }

    #if DEBUG
    func setIsLoadedForTesting(_ loaded: Bool) {
        isLoaded = loaded
    }

    func setHasAppendedTrackForTesting(_ value: Bool, url: URL? = nil) {
        hasAppendedTrack = value
        appendedURL = url
    }

    func setDidAdvanceToAppendedTrackForTesting(_ value: Bool) {
        didAdvanceToAppendedTrack = value
    }

    func setIsPlayingForTesting(_ value: Bool) {
        isPlaying = value
    }

    func setEntryIDsForTesting(active: Int64?, appended: Int64?) {
        activeEntryID = active
        appendedEntryID = appended
    }
    #endif

    func configureStreamRecord(_ url: URL?) {
        clearStreamRecord(removeFile: true)
        streamRecordURL = url
        streamRecordIsContiguous = url != nil
        guard let mpv else { return }
        mpv_set_property_string(mpv, "stream-record", url?.path ?? "")
    }

    func clearStreamRecord(removeFile: Bool) {
        let url = streamRecordURL
        streamRecordURL = nil
        streamRecordIsContiguous = false
        guard let mpv else { return }
        mpv_set_property_string(mpv, "stream-record", "")
        if removeFile, let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - mpv command/property helpers
    private func withMPVArgs(_ parts: [String], _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32) -> Int32 {
        let cArgs = parts.map { strdup($0) }
        defer { cArgs.forEach { if let ptr = $0 { free(ptr) } } }
        var args: [UnsafePointer<CChar>?] = cArgs.map { $0.map { UnsafePointer($0) } }
        args.append(nil)
        return args.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }

    @discardableResult
    func mpvCommand(_ parts: [String]) -> Int32 {
        guard let mpv else { return -1 }
        return withMPVArgs(parts) { argv in
            mpv_command(mpv, argv)
        }
    }

    func mpvCommandEntryID(_ parts: [String]) -> Int64? {
        guard let mpv else { return nil }
        var result = mpv_node()
        let status = withMPVArgs(parts) { argv in
            mpv_command_ret(mpv, argv, &result)
        }
        guard status >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }
        guard result.format == MPV_FORMAT_NODE_MAP,
              let list = result.u.list,
              list.pointee.num > 0,
              let keys = list.pointee.keys,
              let values = list.pointee.values else {
            return nil
        }
        for index in 0..<Int(list.pointee.num) {
            guard let keyPtr = keys[index] else { continue }
            if strcmp(keyPtr, "playlist_entry_id") == 0, values[index].format == MPV_FORMAT_INT64 {
                return values[index].u.int64
            }
        }
        return nil
    }

    func setPaused(_ paused: Bool) {
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
        let filter = silenceTrimMode.mpvAudioFilterOption() ?? ""
        mpv_set_property_string(mpv, "af", filter)
    }

    private func applyVolume() {
        guard let mpv else { return }
        let control = PlaybackVolume.mpvControl(forOutputGain: volume)
        var scaled = Double(control) * 100
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &scaled)
    }
}
