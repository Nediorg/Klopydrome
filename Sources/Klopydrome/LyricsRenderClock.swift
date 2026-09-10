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

    var currentTime: Double {
        guard isPlaying else { return sampledTime }
        return sampledTime + (Date().timeIntervalSince(sampledAt) * rate)
    }

    var shouldAnimate: Bool { isPlaying }

    func synchronize(time: Double, isPlaying: Bool, rate: Double) {
        sampledTime = time
        sampledAt = Date()
        self.isPlaying = isPlaying
        self.rate = rate
    }
}
