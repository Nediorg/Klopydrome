import Foundation

enum SilenceTrimMode: String, Codable, CaseIterable, Identifiable {
    case off
    case light
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .strong: return "Strong"
        }
    }

    func mpvAudioFilterOption() -> String? {
        switch self {
        case .off:
            return nil
        case .light:
            return "lavfi=[silenceremove=stop_periods=1:stop_threshold=-60dB:stop_duration=1]"
        case .strong:
            return "lavfi=[silenceremove=stop_periods=1:stop_threshold=-50dB:stop_duration=0.5]"
        }
    }
}
