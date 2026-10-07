import SwiftUI
import NavidromeClient

/// Shared physics and geometry for Apple Music-style lyrics:
/// elastic ripple wave, progressive timing delays, and optimized depth-of-field blur.
enum LyricsMotionGeometry {
    /// Ripple travels 8 rows outward from the active line in each direction.
    static let rippleReach = 8

    /// Staggered delay per row (50ms per line distance from active line).
    static func rippleDelay(distance: Int) -> Double {
        let absDist = min(abs(distance), rippleReach)
        return Double(absDist) * 0.050
    }

    /// Attenuation factor: 1.0 at distance 0, linearly dropping to 0 at rippleReach.
    static func rippleInfluence(distance: Int) -> CGFloat {
        let absDist = min(abs(distance), rippleReach)
        return CGFloat(rippleReach - absDist) / CGFloat(rippleReach)
    }

    /// Directional ripple offset:
    /// Lines below (distance > 0) push downwards (+Y).
    /// Lines above (distance < 0) push upwards (-Y).
    /// Active line sits in the elastic opening.
    static func rippleOffset(distance: Int) -> CGFloat {
        let clampedDist = min(max(distance, -rippleReach), rippleReach)
        return CGFloat(clampedDist) * 8.0 * rippleInfluence(distance: distance)
    }

    /// Perspective / focus scale for lines:
    /// Active line expands to ~1.10x with surrounding crest; distant lines settle at 0.98x.
    static func perspectiveScale(
        distance: Int,
        isCurrent: Bool,
        motion: LyricsAnimationMotion
    ) -> CGFloat {
        if motion == .none {
            return isCurrent ? 1.02 : 1.00
        }
        let factor: CGFloat = motion == .subtle ? 0.5 : 1.0
        let focusScale: CGFloat = isCurrent ? (1.0 + 0.075 * factor) : (1.0 - 0.02 * factor)
        let rippleScale: CGFloat = 1.0 + (0.03 * rippleInfluence(distance: distance) * factor)
        return focusScale * rippleScale
    }

    /// Combined vertical offset for a line:
    /// focus upward lift for active line (-3pt) + elastic ripple offset.
    static func totalLineOffset(
        distance: Int,
        isCurrent: Bool,
        motion: LyricsAnimationMotion,
        isBrowsing: Bool
    ) -> CGFloat {
        guard !isBrowsing, motion != .none else { return 0 }
        let factor: CGFloat = motion == .subtle ? 0.5 : 1.0
        let focusOffset: CGFloat = isCurrent ? -3.0 * factor : 0
        let ripple = rippleOffset(distance: distance) * factor
        return focusOffset + ripple
    }

    /// Spring animation with progressive delay.
    /// Uses deep, elastic 0.70s response and 0.58 damping fraction from main.
    static func springAnimation(
        distance: Int,
        motion: LyricsAnimationMotion
    ) -> Animation? {
        let delay = rippleDelay(distance: distance)
        switch motion {
        case .none:
            return nil
        case .subtle:
            return .spring(response: 0.52, dampingFraction: 0.75, blendDuration: 0.10)
                .delay(delay * 0.6)
        case .smooth:
            return .spring(response: 0.70, dampingFraction: 0.58, blendDuration: 0.14)
                .delay(delay)
        }
    }

    /// Depth-of-field blur:
    /// Active line and hovered/browsing lines are crisp (0 blur).
    /// Immediate neighbors have subtle, lightweight blur (0.6pt - 1.0pt).
    /// Distant background lines settle at a gentle 1.4pt depth-of-field (fast & readable, not heavy 2.8pt smear).
    /// Because all lines at distance >= 3 share the exact same blur bucket (1.4pt), their blur value
    /// does not change as the active line moves, allowing CoreAnimation to reuse cached GPU textures
    /// with 0 convolution passes.
    static func lineBlur(
        distance: Int,
        isCurrent: Bool,
        isBrowsing: Bool,
        isHovering: Bool,
        blurEnabled: Bool
    ) -> CGFloat {
        guard blurEnabled else { return 0 }
        if isBrowsing || isHovering || isCurrent { return 0 }
        let absDist = abs(distance)
        switch absDist {
        case 1:
            return 0.6
        case 2:
            return 1.0
        default:
            return 1.4
        }
    }

    /// Fast, monotonic blur transition: settles in 160ms without overshoot or ringing,
    /// allowing CoreAnimation to cache rasterized textures immediately.
    static let blurAnimation: Animation = .easeOut(duration: 0.16)
}
