import Foundation
import NavidromeClient

enum ReplayGainMode: String, Codable, CaseIterable, Identifiable {
    case track
    case album
    case off

    var id: String { rawValue }

    var mpvValue: String {
        switch self {
        case .track: return "track"
        case .album: return "album"
        case .off: return "no"
        }
    }

    var label: String {
        switch self {
        case .track: return "By Track"
        case .album: return "By Album"
        case .off: return "Off"
        }
    }
}

enum AutomixLoudness {
    static let defaultPreampDB: Float = 0

    static let preampRange: ClosedRange<Float> = -12 ... 12

    static func clampPreamp(_ preampDB: Float) -> Float {
        min(preampRange.upperBound, max(preampRange.lowerBound, preampDB))
    }

    static func formatDecibels(_ decibels: Float) -> String {
        let value = (decibels * 10).rounded() / 10
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    static func linearGain(forDecibels decibels: Float) -> Float {
        pow(10, decibels / 20)
    }

    static func mpvOptions(
        replayGainMode: ReplayGainMode,
        preampDB: Float,
        silenceTrimMode: SilenceTrimMode
    ) -> [(name: String, value: String)] {
        let preamp = formatDecibels(clampPreamp(preampDB))
        let fallback = replayGainMode == .off ? "0" : preamp
        var options = [
            ("replaygain", replayGainMode.mpvValue),
            ("replaygain-preamp", replayGainMode == .off ? "0" : preamp),
            ("replaygain-fallback", fallback),
            ("replaygain-clip", "no")
        ]
        if let filter = silenceTrimMode.mpvAudioFilterOption() {
            options.append(("af", filter))
        }
        return options
    }

    static func fallbackGainDB(
        mode: ReplayGainMode,
        preampDB: Float,
        replayGain: SubsonicReplayGain?
    ) -> Float? {
        guard mode != .off else { return 0 }
        guard let replayGain else { return nil }

        let rawGain: Double?
        let peak: Double?
        switch mode {
        case .album:
            rawGain = replayGain.albumGain ?? replayGain.trackGain ?? replayGain.fallbackGain ?? replayGain.baseGain
            peak = replayGain.albumPeak ?? replayGain.trackPeak
        case .track:
            rawGain = replayGain.trackGain ?? replayGain.albumGain ?? replayGain.fallbackGain ?? replayGain.baseGain
            peak = replayGain.trackPeak ?? replayGain.albumPeak
        case .off:
            return 0
        }

        guard let rawGain else { return nil }
        var gain = Float(rawGain) + clampPreamp(preampDB)
        if let peak, peak > 0 {
            let maxGain = Float(-20.0 * log10(peak))
            gain = min(gain, maxGain)
        }
        return min(24.0, max(-60.0, gain))
    }
}
