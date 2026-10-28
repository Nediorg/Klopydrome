import Foundation

/// Keeps the user-facing 0...1 volume control consistent across AVFoundation
/// and libmpv with a natural non-linear psychoacoustic audio taper (cubic curve).
///
/// Human loudness perception is logarithmic (Weber-Fechner law). A cubic curve
/// provides generous physical resolution in the lower slider range (0...30%),
/// allowing users to comfortably dial in quiet and late-night listening levels
/// without abrupt drop-offs or loud initial jumps.
enum PlaybackVolume {
    private static let curveExponent: Float = 3.0

    static func outputGain(for control: Float) -> Float {
        let normalized = min(max(control, 0), 1)
        guard normalized > 0 else { return 0 }
        return pow(normalized, curveExponent)
    }

    /// libmpv applies a cubic curve to its `volume` property internally. Feed it
    /// the cube root of the desired output gain so its final gain matches the
    /// AVFoundation path exactly before any engine-specific ReplayGain policy.
    static func mpvControl(forOutputGain gain: Float) -> Float {
        pow(min(max(gain, 0), 1), 1.0 / 3.0)
    }
}
