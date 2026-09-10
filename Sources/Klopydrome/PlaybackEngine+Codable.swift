import Foundation

/// `PlaybackEngine` is persisted inside `ServerConfig`. Decoding is lenient so
/// a config saved before the `ffmpeg` engine was removed (or carrying an
/// unknown value) still loads — it falls back to the recommended MPV engine
/// instead of failing the whole config decode.
extension PlaybackEngine: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "ffmpeg", "mpv": self = .mpv
        case "avFoundation": self = .avFoundation
        default: self = .mpv
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
