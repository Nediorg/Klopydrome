import SwiftUI
import NavidromeClient

/// 0-, 3-state styling for a lyric line.
enum LyricLineState {
    case past, now, future
}

/// Identity skips idle rows on coarse player ticks: only rows whose inputs
/// changed (state/index/time) re-evaluate. `onTap` is deliberately excluded —
/// closures are never equal.
extension KaraokeLine: Equatable {
    static func == (lhs: KaraokeLine, rhs: KaraokeLine) -> Bool {
        lhs.text == rhs.text
            && lhs.lineStart == rhs.lineStart
            && lhs.currentTime == rhs.currentTime
            // renderClock excluded: same @State instance for the whole list.
            && lhs.state == rhs.state
            && lhs.index == rhs.index
            && lhs.activeLineIndex == rhs.activeLineIndex
            && lhs.words == rhs.words
            && lhs.maxLayoutWidth == rhs.maxLayoutWidth
            && lhs.fillLive == rhs.fillLive
    }
}

/// Animated shell around the ticking line content. The 60 fps word-fill
/// `TimelineView` must never share a view node with animated layout
/// properties: its ticks collapse the line-change spring into an instant
/// zoom on Tahoe. Kept in the same file — it exists only for this isolation.
private struct KaraokeLineSpring<Content: View>: View {
    let scale: CGFloat
    let offsetY: CGFloat
    let animation: Animation
    let animationValue: Int?
    let hoverAnimation: Animation
    let hoverValue: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .scaleEffect(scale, anchor: .leading)
            .offset(y: offsetY)
            .animation(animation, value: animationValue)
            .animation(hoverAnimation, value: hoverValue)
    }
}

struct KaraokeLine: View {
    @State private var isHovering = false

    let text: String
    /// Line start in seconds (from `SyncedLine.start`, ms).
    let lineStart: Double?
    /// Fallback sample for non-live states. The live fill reads the render
    /// clock directly through its own scoped `TimelineView`, so ticking never
    /// re-renders the parent list (parent rate proved to be the jank knob:
    /// 30 Hz parent < 10 Hz < 4 Hz).
    let currentTime: Double
    /// Interpolates authoritative samples between player publications.
    /// Read only inside the row's own `TimelineView` — never stored into
    /// parent state, so 60 fps fill invalidates just this row.
    let renderClock: LyricsRenderClock?
    let state: LyricLineState
    /// Identity and current active identity drive only the outer line ripple.
    /// Word colors remain directly tied to `currentTime` with no animation.
    let index: Int
    let activeLineIndex: Int?
    /// Precomputed word cues for this line (from the server's `cueLine`
    /// blocks) — nil falls back to inline-marker parsing.
    var words: [SyncedWord]?
    /// Layout cap for the text column: the largest width the UNSCALED text may
    /// wrap at, so the worst-case scaled line still fits its container.
    var maxLayoutWidth: CGFloat?
    /// Staged fill gate from the owner (clock-derived, no per-row timers):
    /// false while the line-change spring plays (static dim, byte-identical
    /// subtree to a plain line), true after. Default false keeps static
    /// snapshot tests deterministic.
    var fillLive: Bool = false
    let onTap: () -> Void

    /// Derived once at init (all inputs are init-constant): per-frame
    /// `TimelineView` evaluation and 4 Hz parent ticks must not re-parse.
    private let displayWords: [SyncedWord]
    private let wordSync: Bool
    private let reserveStr: String
    private let hasMarkers: Bool

    init(
        text: String,
        lineStart: Double?,
        currentTime: Double,
        renderClock: LyricsRenderClock? = nil,
        state: LyricLineState,
        index: Int = 0,
        activeLineIndex: Int? = nil,
        words: [SyncedWord]? = nil,
        maxLayoutWidth: CGFloat? = nil,
        fillLive: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.text = text
        self.lineStart = lineStart
        self.currentTime = currentTime
        self.renderClock = renderClock
        self.state = state
        self.index = index
        self.activeLineIndex = activeLineIndex
        self.words = words
        self.maxLayoutWidth = maxLayoutWidth
        self.fillLive = fillLive
        self.onTap = onTap
        let parsed = words ?? WordSyncParser.parse(text, lineStart: lineStart)
        self.displayWords = parsed
        let markers = text.contains("<")
        self.hasMarkers = markers
        let reserve = markers ? parsed.map(\.text).joined() : text
        self.reserveStr = reserve
        // Karaoke only when the words actually split the line into more than
        // one chunk AND tile the whole line text (see `isWordSync`).
        self.wordSync = parsed.count > 1 && parsed.map(\.text).joined() == reserve
    }

    /// Largest `focusScale * rippleScale` any line can reach: the active line
    /// at the crest of the ripple. Layout caps divide by this so scaled output
    /// never exceeds the allotted column.
    static let maxLineScale: CGFloat = 1.075 * 1.03

    private var textColumnWidth: CGFloat? {
        maxLayoutWidth.map { max(0, $0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            reserveText
            styledLine
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 4)
        .frame(maxWidth: CGFloat.infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
    }

    /// Invisible bold reserves the FULL bold footprint (width AND wrapped
    /// height) so the visible text's weight change never reflows or shifts
    /// the lines below it.
    private var reserveText: some View {
        Text(reserveString)
            .font(.system(.title3, design: .default).weight(.semibold))
            .foregroundStyle(.clear)
            .frame(maxWidth: textColumnWidth ?? .infinity, alignment: .leading)
    }

    private var styledLine: some View {
        // Same modifiers as before, only split across the isolation node:
        // spring/hover animation live on `KaraokeLineSpring`, ticking content
        // below it. See `KaraokeLineSpring` for why they must not share a node.
        KaraokeLineSpring(
            scale: lineScale,
            offsetY: lineOffset,
            animation: lineAnimation,
            animationValue: activeLineIndex,
            hoverAnimation: .easeOut(duration: 0.12),
            hoverValue: isHovering
        ) {
            styledContent
                // One constant weight (matching the invisible reserve): a
                // regular↔semibold flip changes glyph widths, which makes the
                // syllables visibly slide sideways on every line change. Apple
                // Music's active line differs from the rest only in COLOR.
                .font(.system(.title3, design: .default).weight(.semibold))
                // NO `.animation(value: currentTime)` here: currentTime ticks every
                // 0.25s, and a whole-line animation keyed on it makes SwiftUI treat
                // each tick as a layout-affecting state change. The per-word white
                // fade below is deterministic from the clock and only changes color
                // opacity; position and emphasis still transition on line changes.
                .frame(maxWidth: textColumnWidth ?? .infinity, alignment: .leading)
        }
    }

    /// A transition travels through the surrounding text instead of switching
    /// five discrete rows. The longer reach and lower damping make the active
    /// line's impulse visibly travel outward, then settle like one elastic sheet.
    private static let rippleReach = 8

    private var rippleDelay: Double {
        Double(rippleDistance) * 0.05
    }

    /// This geometry is directional by construction: when the active index moves
    /// down, lower rows close toward the center and upper rows open; moving up
    /// mirrors it. The existing staggered spring then settles each row naturally.
    private var rippleOffset: CGFloat {
        CGFloat(clampedLineDistance) * 8 * rippleInfluence
    }

    private var rippleScale: CGFloat {
        1 + 0.03 * rippleInfluence
    }

    /// The centered line takes the crest of the wave: a stronger rise and
    /// enlargement makes the lyric handoff read as an intentional spring, not
    /// just a color change.
    private var focusScale: CGFloat {
        state == .now ? 1.075 : 0.98
    }

    private var focusOffset: CGFloat {
        state == .now ? -3 : 0
    }

    private var lineScale: CGFloat { focusScale * rippleScale }

    private var lineOffset: CGFloat { focusOffset + rippleOffset }

    private var lineAnimation: Animation {
        .spring(response: 0.7, dampingFraction: 0.58, blendDuration: 0.14)
            .delay(rippleDelay)
    }

    private var lineDistance: Int {
        index - (activeLineIndex ?? index)
    }

    private var rippleDistance: Int {
        min(abs(lineDistance), Self.rippleReach)
    }

    private var clampedLineDistance: Int {
        min(max(lineDistance, -Self.rippleReach), Self.rippleReach)
    }

    private var rippleInfluence: CGFloat {
        CGFloat(Self.rippleReach - rippleDistance) / CGFloat(Self.rippleReach)
    }

    /// The colored content of the line. Word-synced active lines light each word
    /// up individually; every other line is the plain whole-line text. One
    /// static `Text` path for both modes — no per-row `TimelineView`, so the
    /// word line keeps the same spring behavior as a plain synced line.
    /// One subtree shape per mode, never swapped mid-life: word rows are
    /// always multi-run `Text` (past/future uniformly dim, active per-word
    /// live), plain rows always single `Text`. A static→live subtree swap in
    /// the handoff transaction collapses the spring into an instant zoom.
    /// The live fill reads the row's own clock (scoped 60 fps invalidation);
    /// before the fill gate it shows the same multi-run shape statically dim.
    private var styledContent: some View {
        Group {
            if isWordSync && state == .now && fillLive, let renderClock {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !renderClock.shouldAnimate)) { _ in
                    wordText(at: renderClock.currentTime)
                }
            } else if isWordSync {
                wordText(at: currentTime)
            } else {
                Text(reserveString).foregroundStyle(lineColor)
            }
        }
    }

    /// Per-word colors resolved from the owner-fed clock (10 Hz). Non-active
    /// rows share the uniform state color; only the active row reads live
    /// time. Graph shape is identical in every state — only opacities change,
    /// so layout never reflows mid-line and the spring survives handoff.
    private func wordText(at time: Double) -> Text {
        displayWords.enumerated().reduce(Text("")) { partial, entry in
            let (offset, word) = entry
            let nextStart = offset + 1 < displayWords.count ? displayWords[offset + 1].start : nil
            let color: Color = state == .now
                ? wordColor(word, nextStart: nextStart, currentTime: time)
                : lineColor
            return partial + Text(word.text).foregroundStyle(color)
        }
    }

    /// Word-by-word coloring only when the words actually split the line into
    /// more than one chunk AND tile the whole line text. A single chunk (a
    /// lone marker at the start: `<00:05.00>go`, or a line-level cue without
    /// word splits) has nothing to karaoke; a partial cover (multi-agent
    /// tracks, or un-cued gaps such as "(whisper)") falls back to whole-line
    /// coloring so no text is dropped on the active line.
    private var isWordSync: Bool { wordSync }
    /// Raw text carries inline `<m:ss.xx>` markers that must be stripped from
    /// the reserve string even when they don't split the line (see `isWordSync`).
    private var hasInlineMarkers: Bool { hasMarkers }

    /// The marker-free string used by the invisible bold reserve, so it wraps
    /// exactly like the styled text.
    private var reserveString: String { reserveStr }

    /// Active-line karaoke colors. A fresh cue begins at pure white, then
    /// gently settles to the quieter color of a sung word. Upcoming words stay
    /// dim. The opacity is clock-derived, never a SwiftUI transaction, so it
    /// cannot affect line layout or the native scroll viewport.
    private func wordColor(
        _ word: SyncedWord,
        nextStart: Double?,
        currentTime: Double
    ) -> Color {
        let sungAt = word.end ?? nextStart ?? .greatestFiniteMagnitude
        return Color.primary.opacity(Self.wordSettledOpacity(
            at: currentTime,
            wordStart: word.start,
            sungAt: sungAt
        ))
    }

    /// A white cue decays through a 280 ms smoothstep curve to the settled
    /// 85% opacity. For unusually short cue windows, the duration contracts to
    /// the available window so an older cue never brightens after its end.
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

    private var lineColor: Color {
        if state != .now && isHovering {
            return AMColor.primaryText.opacity(0.85)
        }
        switch state {
        case .now: return .primary
        case .past: return Color.secondary.opacity(0.75)
        case .future: return Color.secondary.opacity(0.5)
        }
    }
}
