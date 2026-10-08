import Foundation
import Observation

/// A clock for sub-frame lyric rendering. The player publishes authoritative
/// samples at a modest cadence, while this clock interpolates between them for
/// visuals only; seeking and line-follow still use the authoritative samples.
@MainActor
@Observable
final class LyricsRenderClock {
    private var sampledTime: Double = 0
    private var sampledAt = Date()
    private var isPlaying = false
    private var rate: Double = 1
    /// Extrapolation ceiling: if player samples stall (e.g. network buffering),
    /// the clock freezes after 0.35s instead of running away into the future.
    private let maxExtrapolation: TimeInterval = 0.35

    var currentTime: Double {
        guard isPlaying else { return sampledTime }
        let elapsed = min(maxExtrapolation, Date().timeIntervalSince(sampledAt))
        return sampledTime + (elapsed * rate)
    }

    var shouldAnimate: Bool {
        isPlaying && Date().timeIntervalSince(sampledAt) < maxExtrapolation
    }

    func synchronize(time: Double, isPlaying: Bool, rate: Double) {
        if self.isPlaying && !isPlaying {
            sampledTime = currentTime
        } else {
            sampledTime = time
        }
        sampledAt = Date()
        self.isPlaying = isPlaying
        self.rate = rate
    }
}
