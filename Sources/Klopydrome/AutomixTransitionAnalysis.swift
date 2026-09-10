import AVFoundation
import Foundation

/// A transition selected from the measured edges of two tracks.
struct AutomixTransitionPlan: Equatable, Sendable {
    enum Basis: String, Sendable {
        case silence
        case onset
        case fallback
    }

    let fadeOutStart: Double
    let fadeDuration: Double
    let incomingLeadIn: Double
    let basis: Basis
}

/// RMS envelopes sampled at a fixed cadence from the beginning and end of a
/// decoded local audio file. Values are dBFS and are chronological in both arrays.
struct AutomixEdgeProfile: Sendable {
    let frameDuration: Double
    let leadingDBFS: [Float]
    let trailingDBFS: [Float]
}

enum AutomixTransitionPlanner {
    static let analysisWindow: Double = 12
    static let silenceThresholdDBFS: Float = -45
    static let minimumFade: Double = 1
    static let maximumFade: Double = 12
    static let defaultFade: Double = 5

    static func plan(
        currentDuration: Double,
        outgoing: AutomixEdgeProfile?,
        incoming: AutomixEdgeProfile?,
        preferredFadeDuration: Double? = nil
    ) -> AutomixTransitionPlan {
        guard currentDuration > 0 else {
            return AutomixTransitionPlan(
                fadeOutStart: 0,
                fadeDuration: defaultFade,
                incomingLeadIn: 0,
                basis: .fallback
            )
        }

        let tailSilence = outgoing.map(trailingSilenceDuration) ?? 0
        let headSilence = incoming.map(leadingSilenceDuration) ?? 0
        let candidate = preferredFadeDuration ?? max(tailSilence, headSilence)
        var fadeDuration = boundedFade(candidate)
        var basis: AutomixTransitionPlan.Basis =
            max(tailSilence, headSilence) >= minimumFade ? .silence : .fallback
        var fadeOutStart = max(0, currentDuration - fadeDuration)

        if preferredFadeDuration == nil,
           basis != .silence,
           let outgoing,
           let peak = nearestOnset(in: outgoing, targetSecondsFromTail: fadeDuration) {
            let earliest = max(0, currentDuration - maximumFade)
            let latest = max(0, currentDuration - minimumFade)
            fadeOutStart = min(latest, max(earliest, currentDuration - peak))
            fadeDuration = currentDuration - fadeOutStart
            basis = .onset
        }

        return AutomixTransitionPlan(
            fadeOutStart: fadeOutStart,
            fadeDuration: fadeDuration,
            incomingLeadIn: min(fadeDuration, headSilence),
            basis: basis
        )
    }

    private static func boundedFade(_ candidate: Double) -> Double {
        min(maximumFade, max(minimumFade, candidate > 0 ? candidate : defaultFade))
    }

    private static func trailingSilenceDuration(_ profile: AutomixEdgeProfile) -> Double {
        let frames = profile.trailingDBFS.reversed().prefix { $0 <= silenceThresholdDBFS }.count
        return Double(frames) * profile.frameDuration
    }

    private static func leadingSilenceDuration(_ profile: AutomixEdgeProfile) -> Double {
        let frames = profile.leadingDBFS.prefix { $0 <= silenceThresholdDBFS }.count
        return Double(frames) * profile.frameDuration
    }

    /// Finds a local energy maximum close to the nominal fade start. This is a
    /// lightweight onset proxy when a real silent outro is not available.
    private static func nearestOnset(
        in profile: AutomixEdgeProfile,
        targetSecondsFromTail: Double
    ) -> Double? {
        let values = profile.trailingDBFS
        guard values.count >= 3 else { return nil }
        let target = max(1, values.count - 1 - Int(targetSecondsFromTail / profile.frameDuration))
        let radius = max(1, Int(0.6 / profile.frameDuration))
        let lower = max(1, target - radius)
        let upper = min(values.count - 2, target + radius)
        guard lower <= upper else { return nil }

        let candidates = (lower...upper).filter {
            values[$0] > values[$0 - 1] && values[$0] >= values[$0 + 1]
        }
        guard let nearest = candidates.min(by: { abs($0 - target) < abs($1 - target) }) else {
            return nil
        }
        return Double(values.count - 1 - nearest) * profile.frameDuration
    }
}

enum AutomixAudioAnalyzer {
    static func edgeProfile(for url: URL) async -> AutomixEdgeProfile? {
        guard url.isFileURL else { return nil }
        return await Task.detached(priority: .utility) {
            makeEdgeProfile(for: url)
        }.value
    }

    private static func makeEdgeProfile(for url: URL) -> AutomixEdgeProfile? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }

        let requestedFrames = AVAudioFramePosition(sampleRate * AutomixTransitionPlanner.analysisWindow)
        let edgeFrames = min(file.length, requestedFrames)
        let start = rmsEnvelope(file: file, format: format, start: 0, frames: edgeFrames)
        let tailStart = max(0, file.length - edgeFrames)
        let tail = rmsEnvelope(file: file, format: format, start: tailStart, frames: edgeFrames)
        guard !start.isEmpty || !tail.isEmpty else { return nil }
        return AutomixEdgeProfile(
            frameDuration: 0.1,
            leadingDBFS: start,
            trailingDBFS: tail
        )
    }

    private static func rmsEnvelope(
        file: AVAudioFile,
        format: AVAudioFormat,
        start: AVAudioFramePosition,
        frames: AVAudioFramePosition
    ) -> [Float] {
        guard frames > 0,
              frames <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)
              ) else {
            return []
        }
        file.framePosition = start
        guard (try? file.read(into: buffer, frameCount: AVAudioFrameCount(frames))) != nil,
              let channels = buffer.floatChannelData else {
            return []
        }

        let sampleCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        let window = max(1, Int(format.sampleRate * 0.1))
        var result: [Float] = []
        for offset in stride(from: 0, to: sampleCount, by: window) {
            let upper = min(sampleCount, offset + window)
            var energy: Float = 0
            for index in offset..<upper {
                for channel in 0..<channelCount {
                    let sample = channels[channel][index]
                    energy += sample * sample
                }
            }
            let count = Float((upper - offset) * channelCount)
            let rms = sqrt(energy / max(1, count))
            result.append(20 * log10(max(rms, 0.000_01)))
        }
        return result
    }
}
