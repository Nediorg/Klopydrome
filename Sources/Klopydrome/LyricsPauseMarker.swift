import SwiftUI

/// A timestamped silence in synchronized lyrics. The large midline ellipsis
/// fills from leading edge during the silence, then returns to its quiet state
/// as soon as the following lyric becomes active.
/// `progress`/`pauseRange` clamp outside the pause window, so `Equatable`
/// skips the marker on coarse ticks except while its own pause is live
/// (`onTap` excluded — closures are never equal).
extension LyricsPauseMarker: Equatable {
    static func == (lhs: LyricsPauseMarker, rhs: LyricsPauseMarker) -> Bool {
        lhs.progress == rhs.progress
            && lhs.pauseRange == rhs.pauseRange
    }
}

struct LyricsPauseMarker: View {
    let progress: Double
    let renderClock: LyricsRenderClock?
    let pauseRange: ClosedRange<Double>?
    let onTap: () -> Void

    init(
        progress: Double,
        renderClock: LyricsRenderClock? = nil,
        pauseRange: ClosedRange<Double>? = nil,
        onTap: @escaping () -> Void
    ) {
        self.progress = progress
        self.renderClock = renderClock
        self.pauseRange = pauseRange
        self.onTap = onTap
    }

    var body: some View {
        markerContent
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityLabel("Пауза в тексте")
    }

    @ViewBuilder
    private var markerContent: some View {
        if let renderClock, let pauseRange {
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !renderClock.shouldAnimate)) { _ in
                marker(progress: Self.progress(
                    at: renderClock.currentTime,
                    from: pauseRange.lowerBound,
                    until: pauseRange.upperBound
                ))
            }
        } else {
            marker(progress: progress)
        }
    }

    private func marker(progress: Double) -> some View {
        ZStack {
            markerText
                .foregroundStyle(Color.secondary.opacity(0.5))
            markerText
                .foregroundStyle(AMColor.primaryText)
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(
                                width: proxy.size.width * Self.fillProgress(for: progress),
                                height: proxy.size.height
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
        }
    }

    /// Maps the audio clock to the normalized fill position. Keeping this pure
    /// makes the marker deterministic for seeks as well as normal playback.
    static func progress(at currentTime: Double, from start: Double, until end: Double) -> Double {
        guard end > start else { return currentTime >= end ? 1 : 0 }
        return min(max((currentTime - start) / (end - start), 0), 1)
    }

    /// At the end of a silence the active overlay is deliberately removed. The
    /// next lyric owns the accent, while the completed pause returns to gray.
    static func fillProgress(for progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped < 1 ? clamped : 0
    }

    private var markerText: Text { Text("⋯") }
}
