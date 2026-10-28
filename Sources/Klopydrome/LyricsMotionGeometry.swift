import SwiftUI
import NavidromeClient

enum LyricsMotionGeometry {
    static let rippleReach = 8

    static func rippleDelay(distance: Int) -> Double {
        let absDist = min(abs(distance), rippleReach)
        return Double(absDist) * 0.050
    }

    static func rippleInfluence(distance: Int) -> CGFloat {
        let absDist = min(abs(distance), rippleReach)
        return CGFloat(rippleReach - absDist) / CGFloat(rippleReach)
    }

    static func rippleOffset(distance: Int) -> CGFloat {
        let clampedDist = min(max(distance, -rippleReach), rippleReach)
        return CGFloat(clampedDist) * 8.0 * rippleInfluence(distance: distance)
    }

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
            return .spring(response: 0.70, dampingFraction: 0.78, blendDuration: 0.14)
                .delay(delay)
        }
    }

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

    static let blurAnimation: Animation = .easeOut(duration: 0.16)
}
