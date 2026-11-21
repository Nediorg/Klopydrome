import Foundation

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

    static func gains(progress: Double) -> CrossfadeGains {
        let clamped = min(1.0, max(0.0, progress))
        let angle = clamped * (.pi / 2.0)
        return CrossfadeGains(
            outgoing: Float(cos(angle)),
            incoming: Float(sin(angle))
        )
    }

    static func stepProgress(elapsed: Double, duration: Double) -> Double {
        let totalSeconds = max(1, Int(duration.rounded()))
        let currentStep = min(totalSeconds, max(0, Int(floor(max(0, elapsed)))) + 1)
        return Double(currentStep) / Double(totalSeconds)
    }
}
