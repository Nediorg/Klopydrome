import Foundation

struct AutomixCrossfadeGains: Equatable {
    let outgoing: Float
    let incoming: Float
}

enum AutomixCrossfade {
    /// Equal-power gains preserve perceived energy through the overlap. The
    /// MPV contexts reserve 3 dB of ReplayGain headroom for their peak sum.
    static func gains(progress: Double) -> AutomixCrossfadeGains {
        let clampedProgress = min(max(progress, 0), 1)
        let angle = clampedProgress * .pi / 2
        return AutomixCrossfadeGains(
            outgoing: Float(cos(angle)),
            incoming: Float(sin(angle))
        )
    }

    static func fallbackPlan(
        currentDuration: Double,
        preferredFadeDuration: Double
    ) -> AutomixTransitionPlan {
        AutomixTransitionPlanner.plan(
            currentDuration: currentDuration,
            outgoing: nil,
            incoming: nil,
            preferredFadeDuration: preferredFadeDuration
        )
    }
}
