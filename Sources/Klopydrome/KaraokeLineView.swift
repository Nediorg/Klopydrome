import SwiftUI
import NavidromeClient

/// 0-, 3-state styling for a lyric line.
enum LyricLineState {
    case past, now, future
}

/// Identity skips idle rows on coarse player ticks: only rows whose inputs
/// changed (state/visualDistance/fillLive) re-evaluate. `onTap` is deliberately excluded.
extension KaraokeLine: Equatable {
    static func == (lhs: KaraokeLine, rhs: KaraokeLine) -> Bool {
        lhs.text == rhs.text
            && lhs.state == rhs.state
            && lhs.index == rhs.index
            && lhs.words == rhs.words
            && lhs.maxLayoutWidth == rhs.maxLayoutWidth
            && lhs.fillLive == rhs.fillLive
            && lhs.isBrowsing == rhs.isBrowsing
            && lhs.fontSize == rhs.fontSize
            && lhs.motion == rhs.motion
            && lhs.blurEnabled == rhs.blurEnabled
            && lhs.visualDistance == rhs.visualDistance
    }
}

/// Animated shell around the ticking line content. Isolates layout springs
/// and depth-of-field blur from the 60 fps word-fill TimelineView.
private struct KaraokeLineSpring<Content: View>: View {
    let scale: CGFloat
    let offsetY: CGFloat
    let blur: CGFloat
    let opacity: Double
    let animation: Animation?
    let animationValue: Int?
    let isBrowsing: Bool
    let hoverAnimation: Animation
    let hoverValue: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .scaleEffect(scale, anchor: .leading)
            .offset(y: offsetY)
            .opacity(opacity)
            .animation(animation, value: animationValue)
            .blur(radius: blur)
            .animation(LyricsMotionGeometry.blurAnimation, value: blur)
            .animation(.easeInOut(duration: 0.20), value: isBrowsing)
            .animation(hoverAnimation, value: hoverValue)
    }
}

struct KaraokeLine: View {
    @State private var isHovering = false

    let text: String
    /// Line start in seconds (from `SyncedLine.start`, ms).
    let lineStart: Double?
    /// Fallback sample for non-live states.
    let currentTime: Double
    /// Interpolates authoritative samples between player publications.
    let renderClock: LyricsRenderClock?
    let state: LyricLineState
    let index: Int
    let activeLineIndex: Int?
    let scrollDirection: Int
    /// Precomputed word cues for this line.
    var words: [SyncedWord]?
    /// Layout cap for the text column.
    var maxLayoutWidth: CGFloat?
    /// Retained for compatibility.
    var fillLive: Bool = false
    /// True when user is browsing/scrolling: disables blur and lifts opacity for readability.
    var isBrowsing: Bool = false
    var fontSize: LyricsFontSize = .standard
    var motion: LyricsAnimationMotion = .smooth
    var blurEnabled: Bool = true
    let onTap: () -> Void

    private let displayWords: [SyncedWord]
    private let wordSync: Bool
    private let reserveStr: String

    init(
        text: String,
        lineStart: Double?,
        currentTime: Double,
        renderClock: LyricsRenderClock? = nil,
        state: LyricLineState,
        index: Int = 0,
        activeLineIndex: Int? = nil,
        scrollDirection: Int = 1,
        words: [SyncedWord]? = nil,
        maxLayoutWidth: CGFloat? = nil,
        fillLive: Bool = false,
        isBrowsing: Bool = false,
        fontSize: LyricsFontSize = .standard,
        motion: LyricsAnimationMotion = .smooth,
        blurEnabled: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.text = text
        self.lineStart = lineStart
        self.currentTime = currentTime
        self.renderClock = renderClock
        self.state = state
        self.index = index
        self.activeLineIndex = activeLineIndex
        self.scrollDirection = scrollDirection
        self.words = words
        self.maxLayoutWidth = maxLayoutWidth
        self.fillLive = fillLive
        self.isBrowsing = isBrowsing
        self.fontSize = fontSize
        self.motion = motion
        self.blurEnabled = blurEnabled
        self.onTap = onTap
        let parsed = words ?? WordSyncParser.parse(text, lineStart: lineStart)
        self.displayWords = parsed
        let markers = text.contains("<")
        let reserve = markers ? parsed.map(\.text).joined() : text
        self.reserveStr = reserve
        self.wordSync = parsed.count > 1 && parsed.map(\.text).joined() == reserve
    }

    /// Maximum line scale reached by active line (1.15).
    static let maxLineScale: CGFloat = 1.15

    private var textColumnWidth: CGFloat? {
        maxLayoutWidth.map { max(0, $0) }
    }

    var body: some View {
        styledLine
            .multilineTextAlignment(.leading)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: onTap)
    }

    private var styledLine: some View {
        KaraokeLineSpring(
            scale: lineScale,
            offsetY: lineOffset,
            blur: lineBlur,
            opacity: lineOpacity,
            animation: lineAnimation,
            animationValue: activeLineIndex,
            isBrowsing: isBrowsing,
            hoverAnimation: .easeOut(duration: 0.10),
            hoverValue: isHovering
        ) {
            styledContent
                .font(fontSize.font)
                .frame(maxWidth: textColumnWidth ?? .infinity, alignment: .leading)
        }
    }

    var visualDistance: Int {
        guard let active = activeLineIndex else { return 999 }
        let dist = index - active
        return max(-8, min(8, dist))
    }

    private var lineDistance: Int {
        index - (activeLineIndex ?? index)
    }

    private var lineScale: CGFloat {
        LyricsMotionGeometry.perspectiveScale(
            distance: lineDistance,
            isCurrent: state == .now,
            motion: motion
        )
    }

    private var lineOffset: CGFloat {
        LyricsMotionGeometry.totalLineOffset(
            distance: lineDistance,
            isCurrent: state == .now,
            motion: motion,
            isBrowsing: isBrowsing
        )
    }

    private var lineAnimation: Animation? {
        LyricsMotionGeometry.springAnimation(
            distance: lineDistance,
            motion: motion
        )
    }

    // MARK: - Depth-of-field & Opacity

    private var lineBlur: CGFloat {
        LyricsMotionGeometry.lineBlur(
            distance: lineDistance,
            isCurrent: state == .now || index == activeLineIndex,
            isBrowsing: isBrowsing,
            isHovering: isHovering,
            blurEnabled: blurEnabled
        )
    }

    private var lineOpacity: Double {
        if isHovering { return 1.0 }
        if isBrowsing {
            return state == .now ? 1.0 : 0.85
        }
        switch state {
        case .now:
            return 1.0
        case .past:
            return abs(lineDistance) <= 1 ? 0.48 : 0.30
        case .future:
            return abs(lineDistance) <= 1 ? 0.52 : 0.34
        }
    }

    @ViewBuilder
    private var styledContent: some View {
        if wordSync && state == .now && fillLive, let renderClock {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !renderClock.shouldAnimate)) { _ in
                wordText(at: renderClock.currentTime)
            }
        } else if wordSync && state == .now {
            wordText(at: currentTime)
        } else {
            plainTextContent
        }
    }

    private var plainTextContent: some View {
        Text(reserveStr)
            .foregroundStyle(plainTextColor)
            .frame(maxWidth: textColumnWidth ?? .infinity, alignment: .leading)
    }

    private var plainTextColor: Color {
        if isHovering {
            return AMColor.primaryText
        }
        return state == .now ? Color.white : Color.white.opacity(0.85)
    }

    private func wordText(at time: Double) -> Text {
        displayWords.enumerated().reduce(Text("")) { partial, entry in
            let (offset, word) = entry
            let nextStart = offset + 1 < displayWords.count ? displayWords[offset + 1].start : nil
            let color: Color = state == .now
                ? wordColor(word, nextStart: nextStart, currentTime: time)
                : plainTextColor
            return partial + Text(word.text).foregroundStyle(color)
        }
    }

    private func wordColor(
        _ word: SyncedWord,
        nextStart: Double?,
        currentTime: Double
    ) -> Color {
        let sungAt = word.end ?? nextStart ?? .greatestFiniteMagnitude
        return Color.white.opacity(Self.wordSettledOpacity(
            at: currentTime,
            wordStart: word.start,
            sungAt: sungAt
        ))
    }

    /// Retained helper for existing tests and smoothstep settling.
    static func wordSettledOpacity(
        at currentTime: Double,
        wordStart: Double,
        sungAt: Double
    ) -> Double {
        guard currentTime >= wordStart else { return 0.5 }
        let availableDuration = max(0, sungAt - wordStart)
        let fadeDuration = min(0.28, availableDuration)
        guard fadeDuration > 0 else { return 0.85 }
        let progress = min((currentTime - wordStart) / fadeDuration, 1)
        let smoothProgress = progress * progress * (3 - (2 * progress))
        return 1 - (0.15 * smoothProgress)
    }
}
