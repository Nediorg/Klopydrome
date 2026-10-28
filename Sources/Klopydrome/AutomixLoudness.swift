import Foundation

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
    static let crossfadeHeadroomDB: Float = -3

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
