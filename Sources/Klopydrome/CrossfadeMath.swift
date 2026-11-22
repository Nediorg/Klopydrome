import Foundation
import NavidromeClient

struct CrossfadeGains: Equatable {
    let outgoing: Float
    let incoming: Float
}

struct ActiveCrossfade: Equatable {
    let successorID: String
    var startTime: CFAbsoluteTime
    let duration: Double
    var pausedAt: CFAbsoluteTime?
}

enum CrossfadeMath {
    static let defaultDuration: Double = 5.0
    static let minDuration: Double = 1.0
    static let maxDuration: Double = 12.0

    static func clampDuration(_ duration: Double) -> Double {
        min(maxDuration, max(minDuration, duration))
    }

    static func effectiveDuration(configured: Double, remaining: Double) -> Double {
        max(0.25, min(configured, remaining))
    }

    static func gains(progress: Double) -> CrossfadeGains {
        let clamped = min(1.0, max(0.0, progress))
        let angle = clamped * (.pi / 2.0)
        return CrossfadeGains(
            outgoing: Float(cos(angle)),
            incoming: Float(sin(angle))
        )
    }

    static func progress(elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1.0 }
        return min(1.0, max(0.0, elapsed / duration))
    }

    static func trackProgress(remaining: Double, crossfadeDuration: Double) -> Double {
        guard crossfadeDuration > 0 else { return 1.0 }
        let clampedRemaining = max(0.0, remaining)
        return min(1.0, max(0.0, 1.0 - clampedRemaining / crossfadeDuration))
    }

    static func fadeOpacity(elapsed: Double, duration: Double, fadingIn: Bool) -> Double {
        guard duration > 0 else { return fadingIn ? 1.0 : 0.0 }
        let t = min(1.0, max(0.0, elapsed / duration))
        if fadingIn {
            return 1.0 - pow(1.0 - t, 2.0)
        }
        return pow(1.0 - t, 2.0)
    }

    static func stepProgress(elapsed: Double, duration: Double) -> Double {
        let totalSeconds = max(1, Int(duration.rounded()))
        let currentStep = min(totalSeconds, max(0, Int(floor(max(0, elapsed)))) + 1)
        return Double(currentStep) / Double(totalSeconds)
    }
}
