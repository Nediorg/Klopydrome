import Foundation

/// Local playback choices saved only when the app terminates normally.
///
/// These values deliberately live outside `ServerConfig`: they are app-wide UI
/// choices, not server-profile settings, and updating the volume slider must
/// never write to the server configuration.
struct PlaybackExitPreferences: Equatable {
    static let volumeKey = "playbackExitVolume"
    static let shuffleEnabledKey = "playbackExitShuffleEnabled"

    var volume: Float
    var shuffleEnabled: Bool

    init(volume: Float = 1, shuffleEnabled: Bool = false) {
        self.volume = Self.normalized(volume)
        self.shuffleEnabled = shuffleEnabled
    }

    static func load(from defaults: UserDefaults = .standard) -> PlaybackExitPreferences {
        let savedVolume = (defaults.object(forKey: volumeKey) as? NSNumber)?.floatValue ?? 1
        let shuffleEnabled = defaults.object(forKey: shuffleEnabledKey) as? Bool ?? false
        return PlaybackExitPreferences(volume: savedVolume, shuffleEnabled: shuffleEnabled)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(volume, forKey: Self.volumeKey)
        defaults.set(shuffleEnabled, forKey: Self.shuffleEnabledKey)
    }

    private static func normalized(_ volume: Float) -> Float {
        guard volume.isFinite else { return 1 }
        return min(1, max(0, volume))
    }
}
