import Foundation

/// How aggressively trailing silence is removed from the end of a track.
///
/// Trimmed through mpv's `af` chain using libavfilter's `silenceremove`. The
/// graph is wrapped in the `lavfi=[...]` form because `silenceremove`'s option
/// separators (`:`) would otherwise be split by mpv's filter-list parser.
/// `stop_periods=1` trims only the end-of-track silence, never pauses inside
/// the song, and `stop_threshold`/`stop_duration` control how quiet and how
/// long a tail must be before it is cut. Only the MPV engine exposes an audio
/// filter chain, so the AVFoundation path always plays untrimmed.
enum SilenceTrimMode: String, Codable, CaseIterable, Identifiable {
    /// Leave the trailing silence untouched.
    case off
    /// Cut only long, near-digital-silent tails; fades and soft endings keep
    /// their natural decay.
    case light
    /// Cut shorter, less-quiet tails too.
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Выкл"
        case .light: return "Лёгкая"
        case .strong: return "Сильная"
        }
    }

    /// The `af` option value for this mode, or nil to leave the filter chain
    /// empty.
    func mpvAudioFilterOption() -> String? {
        switch self {
        case .off:
            return nil
        case .light:
            return "lavfi=[silenceremove=stop_periods=1:stop_threshold=-60dB:stop_duration=1]"
        case .strong:
            // -45dB/0.3s was cutting quiet fade-outs and reverb tails on
            // real tracks; keep strong meaningfully stronger than light but
            // not so aggressive that it clips musical tails.
            return "lavfi=[silenceremove=stop_periods=1:stop_threshold=-50dB:stop_duration=0.5]"
        }
    }
}
