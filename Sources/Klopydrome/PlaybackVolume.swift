import Foundation

/// Keeps the user-facing 0...1 volume control consistent across AVFoundation
/// and libmpv. The lifted low end leaves room for quiet listening without a
/// hidden mute threshold near the first few slider percent.
enum PlaybackVolume {
    private static let quietRangeLift: Float = 0.15

    /// Converts the slider position into linear output gain. Only an explicit
    /// zero mutes; 5% remains about -40 dB instead of dropping near silence.
    static func outputGain(for control: Float) -> Float {
        let normalized = min(max(control, 0), 1)
        guard normalized > 0 else { return 0 }
        return normalized * (quietRangeLift + (1 - quietRangeLift) * normalized)
    }

    /// libmpv applies a cubic curve to its `volume` property internally. Feed it
    /// the cube root of the desired output gain so its final gain matches the
    /// AVFoundation path exactly before any engine-specific ReplayGain policy.
    static func mpvControl(forOutputGain gain: Float) -> Float {
        pow(min(max(gain, 0), 1), 1.0 / 3.0)
    }
}
