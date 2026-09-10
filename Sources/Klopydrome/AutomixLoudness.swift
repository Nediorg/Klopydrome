import Foundation

/// How the ReplayGain tags embedded in a track are turned into output gain by
/// mpv. This is a playback-wide correction, deliberately independent of the
/// crossfade transition policy so each engine shares one loudness setting.
enum ReplayGainMode: String, Codable, CaseIterable, Identifiable {
    /// Use the track's own ReplayGain value.
    case track
    /// Use the album's ReplayGain value, preserving the album's mastered level.
    case album
    /// Leave gain untouched (mpv `replaygain=no`).
    case off

    var id: String { rawValue }

    /// mpv `replaygain` property value for this mode.
    var mpvValue: String {
        switch self {
        case .track: return "track"
        case .album: return "album"
        case .off: return "no"
        }
    }

    var label: String {
        switch self {
        case .track: return "По треку"
        case .album: return "По альбому"
        case .off: return "Выкл"
        }
    }
}

/// Loudness policy shared by the active and preloaded MPV contexts.
///
/// Track ReplayGain is the correct basis for an automix because adjacent songs
/// are independent. The default −3 dB preamp and identical fallback reserve
/// equal-power crossfade headroom while preserving the relative gain encoded
/// in tags; the preamp is user-adjustable and carries straight through to both
/// mpv ReplayGain options so the perceived level stays consistent whether or
/// not a track carries gain tags.
enum AutomixLoudness {
    /// Equal-power overlap can reach +3 dB for correlated signals.
    static let crossfadeHeadroomDB: Float = -3

    /// Supported preamp range (dB) for the settings UI and clamping.
    static let preampRange: ClosedRange<Float> = -12 ... 12

    static func clampPreamp(_ preampDB: Float) -> Float {
        min(preampRange.upperBound, max(preampRange.lowerBound, preampDB))
    }

    /// Formats a decibel value for mpv options (e.g. "-3", "-3.5").
    static func formatDecibels(_ decibels: Float) -> String {
        let value = (decibels * 10).rounded() / 10
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    /// Converts a decibel correction into the linear gain used by an audio
    /// volume multiplier. Kept here for the forthcoming fade ramp.
    static func linearGain(forDecibels decibels: Float) -> Float {
        pow(10, decibels / 20)
    }

    /// Options must be supplied before `mpv_initialize`, so both contexts
    /// calculate ReplayGain with the same policy from the start of buffering.
    static func mpvOptions(
        replayGainMode: ReplayGainMode,
        preampDB: Float,
        silenceTrimMode: SilenceTrimMode
    ) -> [(name: String, value: String)] {
        let preamp = formatDecibels(clampPreamp(preampDB))
        var options = [
            ("replaygain", replayGainMode.mpvValue),
            ("replaygain-preamp", preamp),
            ("replaygain-fallback", preamp),
            ("replaygain-clip", "no")
        ]
        if let filter = silenceTrimMode.mpvAudioFilterOption() {
            options.append(("af", filter))
        }
        return options
    }
}
