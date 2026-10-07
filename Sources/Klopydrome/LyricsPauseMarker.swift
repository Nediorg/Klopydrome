import SwiftUI

/// A timestamped silence row in synchronized lyrics.
/// Three dots light up sequentially in the final 3 s before the next vocal line,
/// one per second (T-3 s, T-2 s, T-1 s), with a continuous mathematical pulse on each ignition.
/// Outside the countdown window the active dots gently breathe with the music.
/// Participates in the exact same ripple spring, focus scale, and depth-of-field blur as `KaraokeLine`.
extension LyricsPauseMarker: Equatable {
    static func == (lhs: LyricsPauseMarker, rhs: LyricsPauseMarker) -> Bool {
        lhs.pauseRange == rhs.pauseRange
            && lhs.index == rhs.index
            && lhs.isBrowsing == rhs.isBrowsing
            && lhs.isPlaying == rhs.isPlaying
            && lhs.motion == rhs.motion
            && lhs.blurEnabled == rhs.blurEnabled
            && lhs.countdownEnabled == rhs.countdownEnabled
            && lhs.visualDistance == rhs.visualDistance
    }
}

struct LyricsPauseMarker: View {
    @State private var isHovering = false

    let progress: Double
    let renderClock: LyricsRenderClock?
    let pauseRange: ClosedRange<Double>?
    let index: Int
    let activeLineIndex: Int?
    let scrollDirection: Int
    /// `index - activeLineIndex` — drives blur, opacity, scale, and offset identical to `KaraokeLine`.
    let lineDistance: Int
    var isBrowsing: Bool = false
    var isPlaying: Bool = true
    var motion: LyricsAnimationMotion = .smooth
    var blurEnabled: Bool = true
    var countdownEnabled: Bool = true
    let onTap: () -> Void

    private static let dotDiameter: CGFloat = 8.0
    private static let dotSpacing: CGFloat = 8.0

    init(
        progress: Double,
        renderClock: LyricsRenderClock? = nil,
        pauseRange: ClosedRange<Double>? = nil,
        index: Int = 0,
        activeLineIndex: Int? = nil,
        scrollDirection: Int = 1,
        lineDistance: Int = 0,
        isBrowsing: Bool = false,
        isPlaying: Bool = true,
        motion: LyricsAnimationMotion = .smooth,
        blurEnabled: Bool = true,
        countdownEnabled: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.progress = progress
        self.renderClock = renderClock
        self.pauseRange = pauseRange
        self.index = index
        self.activeLineIndex = activeLineIndex
        self.scrollDirection = scrollDirection
        self.lineDistance = lineDistance
        self.isBrowsing = isBrowsing
        self.isPlaying = isPlaying
        self.motion = motion
        self.blurEnabled = blurEnabled
        self.countdownEnabled = countdownEnabled
        self.onTap = onTap
    }

    var body: some View {
        styledMarker
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: onTap)
            .accessibilityLabel("Пауза в тексте".localized)
    }

    private var styledMarker: some View {
        markerContent
            .scaleEffect(markerScale, anchor: .leading)
            .offset(y: markerOffset)
            .opacity(markerOpacity)
            .animation(markerAnimation, value: activeLineIndex)
            .blur(radius: markerBlur)
            .animation(LyricsMotionGeometry.blurAnimation, value: markerBlur)
            .animation(.easeInOut(duration: 0.20), value: isBrowsing)
            .animation(.easeOut(duration: 0.10), value: isHovering)
    }

    var visualDistance: Int {
        guard let active = activeLineIndex else { return 999 }
        let dist = index - active
        return max(-8, min(8, dist))
    }

    // MARK: - Motion & Ripple geometry matching KaraokeLine

    private var isCurrent: Bool {
        lineDistance == 0
    }

    private var markerScale: CGFloat {
        LyricsMotionGeometry.perspectiveScale(
            distance: lineDistance,
            isCurrent: isCurrent,
            motion: motion
        )
    }

    private var markerOffset: CGFloat {
        LyricsMotionGeometry.totalLineOffset(
            distance: lineDistance,
            isCurrent: isCurrent,
            motion: motion,
            isBrowsing: isBrowsing
        )
    }

    private var markerAnimation: Animation? {
        LyricsMotionGeometry.springAnimation(
            distance: lineDistance,
            motion: motion
        )
    }

    // MARK: - Depth-of-field

    private var markerBlur: CGFloat {
        LyricsMotionGeometry.lineBlur(
            distance: lineDistance,
            isCurrent: isCurrent || index == activeLineIndex,
            isBrowsing: isBrowsing,
            isHovering: isHovering,
            blurEnabled: blurEnabled
        )
    }

    private var markerOpacity: Double {
        if isHovering { return 1.0 }
        if isBrowsing {
            return isCurrent ? 1.0 : 0.85
        }
        if isCurrent { return 1.0 }
        return abs(lineDistance) <= 1 ? 0.48 : 0.30
    }

    // MARK: - Content and Countdown

    @ViewBuilder
    private var markerContent: some View {
        let isTimelineActive = isCurrent && isPlaying && countdownEnabled
        if let renderClock, isTimelineActive {
            TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                let current = renderClock.currentTime
                let isActive = isCurrent || isWithinPauseWindow(current: current)
                dotsView(current: current, isActive: isActive)
            }
        } else {
            let current = effectiveCurrentTime
            let isActive = isCurrent || isWithinPauseWindow(current: current)
            dotsView(current: current, isActive: isActive)
        }
    }

    private var effectiveCurrentTime: Double {
        if let renderClock {
            return renderClock.currentTime
        }
        if let pauseRange {
            let duration = max(0.5, pauseRange.upperBound - pauseRange.lowerBound)
            return pauseRange.lowerBound + progress * duration
        }
        return progress * 3.0
    }

    private func isWithinPauseWindow(current: Double) -> Bool {
        guard let pauseRange, pauseRange.upperBound > pauseRange.lowerBound else {
            return isCurrent
        }
        return current >= pauseRange.lowerBound && current <= pauseRange.upperBound
    }

    private func dotsView(current: Double, isActive: Bool) -> some View {
        HStack(spacing: Self.dotSpacing) {
            ForEach(0..<3) { dotIdx in
                let info = dotState(for: dotIdx, current: current, isActive: isActive)
                Circle()
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                    .foregroundStyle(Color.white.opacity(info.opacity))
                    .shadow(color: Color.white.opacity(info.glow * 0.4), radius: 2)
                    .scaleEffect(info.scale)
            }
        }
        .frame(height: 24, alignment: .leading)
    }

    private struct DotVisualState {
        let opacity: Double
        let scale: CGFloat
        let glow: Double
    }

    private func dotState(for dotIdx: Int, current: Double, isActive: Bool) -> DotVisualState {
        if isHovering {
            return DotVisualState(opacity: 0.95, scale: 1.05, glow: 0.35)
        }
        guard isActive else {
            return DotVisualState(opacity: 0.35, scale: 1.0, glow: 0.0)
        }
        if !countdownEnabled {
            return DotVisualState(opacity: 0.95, scale: 1.0, glow: 0.25)
        }

        let duration: Double
        let end: Double
        if let pauseRange, pauseRange.upperBound > pauseRange.lowerBound {
            end = pauseRange.upperBound
            duration = end - pauseRange.lowerBound
        } else {
            end = 3.0
            duration = 3.0
        }

        let countdownWindow = min(3.0, max(0.6, duration))
        let countdownStart = end - countdownWindow
        let step = countdownWindow / 3.0
        let ignitionTime = countdownStart + (Double(dotIdx) * step)

        if current < countdownStart {
            let wave = sin(current * 2.8 + Double(dotIdx) * 0.4) * 0.12
            return DotVisualState(opacity: 0.45 + wave, scale: 1.0, glow: 0.0)
        }

        if current < ignitionTime {
            return DotVisualState(opacity: 0.35, scale: 1.0, glow: 0.0)
        } else {
            let timeSinceIgnition = current - ignitionTime
            let pulseScale: CGFloat = {
                let pulseDuration = 0.22
                if timeSinceIgnition >= 0 && timeSinceIgnition < pulseDuration {
                    let progress = timeSinceIgnition / pulseDuration
                    return 1.0 + 0.28 * CGFloat(sin(progress * .pi))
                }
                return 1.0
            }()
            return DotVisualState(opacity: 1.0, scale: pulseScale, glow: 0.5)
        }
    }

    // MARK: - Static helpers (used by tests)

    /// Maps audio time to the normalized [0, 1] sweep over the final 3.0 s before vocal reentry.
    static func countdownProgress(at currentTime: Double, from start: Double, until end: Double) -> Double {
        let duration = end - start
        guard duration > 0 else { return currentTime >= end ? 1.0 : 0.0 }
        let countdownWindow = min(3.0, max(0.5, duration))
        let countdownStart = end - countdownWindow
        guard currentTime >= countdownStart else { return 0.0 }
        guard currentTime < end else { return 1.0 }
        return min(max((currentTime - countdownStart) / countdownWindow, 0.0), 1.0)
    }

    /// Maps the audio clock to normalized fill position across the entire pause range.
    static func progress(at currentTime: Double, from start: Double, until end: Double) -> Double {
        guard end > start else { return currentTime >= end ? 1 : 0 }
        return min(max((currentTime - start) / (end - start), 0), 1)
    }

    /// Backwards compatibility helper for existing silence reset contract.
    static func fillProgress(for progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped < 1 ? clamped : 0
    }
}
