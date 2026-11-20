import Foundation
import Libmpv
import NavidromeClient

extension MPVPlaybackEngine {
    func append(url: URL, replayGain: SubsonicReplayGain? = nil) {
        hasAppendedTrack = true
        appendedURL = url
        appendedTrackReplayGain = replayGain
        guard mpv != nil else {
            appendedEntryID = nil
            return
        }
        let fallbackDB = AutomixLoudness.fallbackGainDB(
            mode: replayGainMode,
            preampDB: replayGainPreampDB,
            replayGain: replayGain
        )
        if let fallbackDB {
            let opt = "replaygain-fallback=\(AutomixLoudness.formatDecibels(fallbackDB))"
            appendedEntryID = mpvCommandEntryID(["loadfile", url.absoluteString, "append", "-1", opt])
        } else {
            appendedEntryID = mpvCommandEntryID(["loadfile", url.absoluteString, "append"])
        }
    }

    func clearAppended() {
        hasAppendedTrack = false
        appendedURL = nil
        appendedEntryID = nil
        appendedTrackReplayGain = nil
        didAdvanceToAppendedTrack = false
        guard mpv != nil else { return }
        mpvCommand(["playlist-clear"])
    }

    func pruneFinishedHead() {
        didAdvanceToAppendedTrack = false
        guard mpv != nil else { return }
        mpvCommand(["playlist-clear"])
    }

    func skipToAppendedTrack(autoPlay: Bool) {
        clearStreamRecord(removeFile: true)
        let targetEntryID = appendedEntryID
        appendedEntryID = nil
        hasAppendedTrack = false
        appendedURL = nil
        currentTrackReplayGain = appendedTrackReplayGain
        appendedTrackReplayGain = nil
        didAdvanceToAppendedTrack = false
        isLoaded = false
        isEnded = false
        currentTimeValue = 0
        duration = 0
        isSeekable = false
        guard mpv != nil else { return }
        selectAppendedPlaylistEntry(entryID: targetEntryID)
        isPlaying = autoPlay
        setPaused(!autoPlay)
    }

    private func selectAppendedPlaylistEntry(entryID: Int64?) {
        if let entryID {
            activeEntryID = entryID
            if currentPlaylistEntryID() == entryID {
                return
            }
            if let index = playlistIndex(forEntryID: entryID) {
                setInt64Property("playlist-pos", value: index)
                return
            }
        } else {
            activeEntryID = nil
        }
        mpvCommand(["playlist-next", "force"])
    }

    private func readInt64Property(_ name: String) -> Int64? {
        guard let mpv else { return nil }
        var value: Int64 = 0
        guard mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return value
    }

    private func setInt64Property(_ name: String, value: Int64) {
        guard let mpv else { return }
        var mutable = value
        mpv_set_property(mpv, name, MPV_FORMAT_INT64, &mutable)
    }

    private func currentPlaylistEntryID() -> Int64? {
        guard let pos = readInt64Property("playlist-pos"), pos >= 0 else { return nil }
        return readInt64Property("playlist/\(pos)/id")
    }

    private func playlistIndex(forEntryID targetID: Int64) -> Int64? {
        guard let count = readInt64Property("playlist-count"), count > 0 else { return nil }
        for index in 0..<count where readInt64Property("playlist/\(index)/id") == targetID {
            return index
        }
        return nil
    }

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
        activeEntryID = nil
        appendedEntryID = nil
        hasAppendedTrack = false
        appendedURL = nil
        didAdvanceToAppendedTrack = false
        isLoaded = false
        isPlaying = false
        isEnded = false
        isPausedForCache = false
        isSeekable = false
        updateBuffering(false)
        mpvCommand(["stop"])
        currentTimeValue = 0
        duration = 0
    }

    @discardableResult
    func seek(to seconds: Double) -> Bool {
        guard isLoaded else { return false }
        clearStreamRecord(removeFile: true)
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
}
