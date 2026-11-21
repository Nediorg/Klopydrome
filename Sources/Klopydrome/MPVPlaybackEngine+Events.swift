import Foundation
import Libmpv

enum MPVEndFileReason {
    case eof
    case error
    case other

    init(mpvReason: mpv_end_file_reason) {
        switch mpvReason {
        case MPV_END_FILE_REASON_EOF:
            self = .eof
        case MPV_END_FILE_REASON_ERROR:
            self = .error
        default:
            self = .other
        }
    }
}

extension MPVPlaybackEngine {
    func shouldAcceptEvent(entryID: Int64?) -> Bool {
        guard let entryID else { return true }
        return activeEntryID == entryID
    }

    @MainActor func updateBuffering(_ value: Bool) {
        guard isBuffering != value else { return }
        isBuffering = value
        onBufferingUpdate?(value)
    }

    @MainActor func setPausedForCache(_ value: Bool, entryID: Int64? = nil) {
        guard shouldAcceptEvent(entryID: entryID) else { return }
        isPausedForCache = value
        updateBuffering(value)
    }

    @MainActor func applyTimePos(_ pos: Double, entryID: Int64? = nil) {
        guard shouldAcceptEvent(entryID: entryID) else { return }
        currentTimeValue = pos
        updateBuffering(isPausedForCache)
        onTimeUpdate?(pos)
    }

    @MainActor func setDuration(_ d: Double, entryID: Int64? = nil) {
        guard shouldAcceptEvent(entryID: entryID) else { return }
        let normalized = d.isFinite && d > 0 ? d : 0
        duration = normalized
        onDurationUpdate?(normalized)
    }

    @MainActor func setSeekable(_ value: Bool, entryID: Int64? = nil) {
        guard shouldAcceptEvent(entryID: entryID) else { return }
        guard isSeekable != value else { return }
        isSeekable = value
        onSeekableUpdate?(value)
    }

    @MainActor func handleStartFile(entryID: Int64) {
        if entryID == appendedEntryID {
            activeEntryID = entryID
            appendedEntryID = nil
            hasAppendedTrack = false
            appendedURL = nil
            didAdvanceToAppendedTrack = true
            isLoaded = false
            isEnded = false
            duration = 0
            currentTimeValue = 0
            isSeekable = false
            return
        }
        guard shouldAcceptEvent(entryID: entryID) else { return }
        isLoaded = false
        isEnded = false
    }

    @MainActor func handleFileLoaded(entryID: Int64? = nil) {
        guard shouldAcceptEvent(entryID: entryID) else { return }
        isLoaded = true
        isEnded = false
        if let mpv {
            var d: Double = 0
            if mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &d) >= 0 {
                setDuration(d, entryID: entryID)
            }
        }
        onFileLoaded?()
    }

    @MainActor func handleEndFile(entryID: Int64, reason: MPVEndFileReason, errorCode: Int32) {
        if entryID == appendedEntryID && entryID != activeEntryID {
            if reason == .error {
                clearAppended()
            }
            return
        }
        guard activeEntryID == entryID else { return }
        switch reason {
        case .eof:
            handleTrackEnded()
        case .error:
            handleTrackFailure(errorCode: errorCode)
        case .other:
            break
        }
    }

    @MainActor func handleTrackEnded() {
        let completedRecord = streamRecordIsContiguous ? streamRecordURL : nil
        let reachedTime = currentTimeValue
        let recordedDuration = duration
        clearStreamRecord(removeFile: completedRecord == nil)
        if let completedRecord {
            onStreamRecordFinished?(MPVPlaybackEngine.StreamRecordCompletion(
                url: completedRecord,
                reachedTime: reachedTime,
                streamDuration: recordedDuration
            ))
        }
        currentTimeValue = 0
        duration = 0
        guard !isEnded else { return }
        if hasAppendedTrack {
            didAdvanceToAppendedTrack = true
            hasAppendedTrack = false
            appendedURL = nil
            activeEntryID = appendedEntryID
            appendedEntryID = nil
            onTrackEnded?()
        } else {
            didAdvanceToAppendedTrack = false
            activeEntryID = nil
            isLoaded = false
            isEnded = true
            isPlaying = false
            isPausedForCache = false
            updateBuffering(false)
            onTrackEnded?()
        }
    }

    static func mpvErrorIdentifier(_ code: Int32) -> String {
        switch code {
        case -13: return "loading_failed"
        case -16: return "nothing_to_play"
        case -17: return "unknown_format"
        case -18: return "unsupported"
        default: return "error_\(code)"
        }
    }

    @MainActor func handleTrackFailure(errorCode: Int32) {
        guard !isEnded else { return }
        clearStreamRecord(removeFile: true)
        activeEntryID = nil
        appendedEntryID = nil
        hasAppendedTrack = false
        appendedURL = nil
        didAdvanceToAppendedTrack = false
        isLoaded = false
        isEnded = true
        isPlaying = false
        isPausedForCache = false
        updateBuffering(false)
        onFailureCode?(Self.mpvErrorIdentifier(errorCode))
        onFailure?(L10n.format("format.mpv.openFailure", Int(errorCode)))
    }
}

/// Drains the libmpv event loop on a dedicated background serial queue,
/// forwarding state transitions stamped with `playlist_entry_id` to `MainActor`.
final class EventPump: @unchecked Sendable {
    weak var engine: MPVPlaybackEngine?
    var mpv: OpaquePointer?
    let queue = DispatchQueue(label: "mpv.event")
    var lastTimeUpdate: CFAbsoluteTime = 0
    var trackDuration: Double = 0
    private var currentEntryID: Int64?

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
            currentEntryID = nil
        }
    }

    private func dispatch(_ event: UnsafeMutablePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event)
        case MPV_EVENT_START_FILE:
            guard let startPtr = event.pointee.data?.assumingMemoryBound(to: mpv_event_start_file.self) else { return }
            let entryID = startPtr.pointee.playlist_entry_id
            currentEntryID = entryID
            lastTimeUpdate = 0
            trackDuration = 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.handleStartFile(entryID: entryID)
            }
        case MPV_EVENT_FILE_LOADED:
            guard let entryID = currentEntryID else { return }
            lastTimeUpdate = 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.handleFileLoaded(entryID: entryID)
            }
        case MPV_EVENT_END_FILE:
            handleEndFile(event)
        default:
            break
        }
    }

    private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let entryID = currentEntryID,
              let propPtr = event.pointee.data?.assumingMemoryBound(to: mpv_event_property.self) else { return }
        let prop = propPtr.pointee
        let name = String(cString: prop.name)
        switch name {
        case "time-pos":
            guard let dptr = prop.data?.assumingMemoryBound(to: Double.self) else { return }
            handleTimePosChange(dptr.pointee, entryID: entryID)
        case "duration":
            guard let dptr = prop.data?.assumingMemoryBound(to: Double.self) else { return }
            let d = dptr.pointee
            trackDuration = d
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setDuration(d, entryID: entryID)
            }
        case "seekable":
            guard let fptr = prop.data?.assumingMemoryBound(to: Int32.self) else { return }
            let flag = fptr.pointee != 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setSeekable(flag, entryID: entryID)
            }
        case "paused-for-cache":
            guard let fptr = prop.data?.assumingMemoryBound(to: Int32.self) else { return }
            let flag = fptr.pointee != 0
            DispatchQueue.main.async { [weak self] in
                self?.engine?.setPausedForCache(flag, entryID: entryID)
            }
        default:
            break
        }
    }

    private func handleTimePosChange(_ pos: Double, entryID: Int64) {
        let now = CFAbsoluteTimeGetCurrent()
        let isNearEnd = trackDuration > 0 && (trackDuration - pos) <= 0.6
        let minInterval = isNearEnd ? 0.04 : 0.25
        guard now - lastTimeUpdate >= minInterval else { return }
        lastTimeUpdate = now
        DispatchQueue.main.async { [weak self] in
            self?.engine?.applyTimePos(pos, entryID: entryID)
        }
    }

    private func handleEndFile(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let endPtr = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self) else { return }
        let entryID = endPtr.pointee.playlist_entry_id
        if entryID == currentEntryID {
            lastTimeUpdate = 0
            trackDuration = 0
            currentEntryID = nil
        }
        let errorCode = endPtr.pointee.error
        let reason = MPVEndFileReason(mpvReason: endPtr.pointee.reason)
        DispatchQueue.main.async { [weak self] in
            self?.engine?.handleEndFile(entryID: entryID, reason: reason, errorCode: errorCode)
        }
    }
}
