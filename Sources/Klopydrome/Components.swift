import SwiftUI
import NavidromeClient
import AppKit

/// A single source of truth for motion. One interaction class = one consistent
/// spring, per the animation-patterns guidance. All springs are disabled for
/// users who request reduced motion (Reduce Motion in System Settings).
enum Motion {
    static let hover = Animation.snappy(duration: 0.12, extraBounce: 0)
    static let expand = Animation.snappy(duration: 0.2, extraBounce: 0)
    static let feedback = Animation.snappy(duration: 0.15, extraBounce: 0.1)

    static var enabled: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func spring(_ base: Animation) -> Animation {
        enabled ? base : .linear(duration: 0)
    }
}

/// Subtle brighten on hover for icon buttons (Apple Music-style feedback).
struct HoverBrighten: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.14 : 0)
            .animation(Motion.spring(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverBrighten() -> some View {
        modifier(HoverBrighten())
    }
}

/// Visible, rectangular hover for icon-only buttons. A squircle fills the whole
/// button frame on hover, and the hit shape is the SAME rectangle as the fill —
/// so the entire button is hoverable and clickable, not just the glyph. Corners
/// stay rect-ish to read as a normal toolbar button (no round "puffed" padding).
struct HoverFill: ViewModifier {
    var fill: Color = Color.primary.opacity(0.1)
    var cornerRadius: CGFloat = 6
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill.opacity(hovering ? 1 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(Motion.spring(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverFill() -> some View {
        modifier(HoverFill())
    }

    func hoverFill(fill: Color) -> some View {
        modifier(HoverFill(fill: fill))
    }

    func hoverFill(fill: Color, cornerRadius: CGFloat) -> some View {
        modifier(HoverFill(fill: fill, cornerRadius: cornerRadius))
    }

    func hoverFill(cornerRadius: CGFloat) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius))
    }
}

/// Pins an empty-state block to the top of the content area (just under the
/// header row) instead of letting it float in the vertical center of the window.
extension View {
    func emptyStatePinnedToTop(topPadding: CGFloat = 48) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, topPadding)
    }
}

/// Async cover artwork with disk+memory caching and a graceful placeholder.
/// Corner radius scales with size (large covers ~12pt, small thumbnails ~4pt).
struct SongMetadataGrid: View {
    let song: SubsonicSong

    private var rows: [(label: String, value: String?)] {
        [
            ("Альбом", song.album),
            ("Исполнитель", song.artist),
            ("Альбомный исполнитель", song.albumArtist),
            ("Год", song.year.map(String.init)),
            ("Жанр", song.genre),
            ("Битрейт", song.bitRate.map { "\($0) kbps" }),
            ("Формат", song.suffix?.uppercased()),
            ("Длительность", song.duration.map { Player.format(seconds: Double($0)) }),
            ("Номер трека", song.track.map(String.init)),
            ("Диск", song.discNumber.map(String.init)),
            ("Размер", song.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }),
            ("Прослушиваний", song.playCount.map(String.init)),
            ("Путь", song.path),
            ("MusicBrainz ID", song.musicBrainzId)
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let value = row.value {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label.localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// Seek bar for the mini player: a thin track with the current position filled,
/// drag to scrub, click to jump. Custom (not the native `Slider`) because the
/// macOS `Slider`'s invisible hit area extends past the visible track, which
/// made its draggable bounds drift off the track and shadow the rating stars
/// directly above it. A bounded `DragGesture` keeps the hit target exactly on the
/// track.
struct PlaybackSlider: View {
    @Environment(AppState.self) private var app

    var trackOpacity: Double = 0.15
    var progressColor: Color = AMColor.accent
    var progressOpacity: Double = 1

    /// Progress preview while the user drags; nil falls back to live player time.
    @State private var dragProgress: CGFloat?

    private let trackHeight: CGFloat = 6

    private var duration: Double { app.player.trackDuration }

    private var trackProgress: CGFloat {
        if let dragProgress { return dragProgress }
        guard app.player.trackDuration > 0 else { return 0 }
        return CGFloat(min(max(app.player.currentTime / app.player.trackDuration, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .bottomLeading) {
                Capsule()
                    .fill(.white.opacity(trackOpacity))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(progressColor.opacity(progressOpacity))
                    .frame(width: max(width * trackProgress, trackHeight), height: trackHeight)
            }
            .frame(width: width, height: trackHeight)
            .clipped()
            .frame(height: 18, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(drag(width: width))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Позиция воспроизведения".localized)
            .accessibilityValue(app.player.formattedCurrentTime())
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 10.0 : -10.0
                guard app.player.trackDuration > 0 else { return }
                app.player.seek(to: min(max(app.player.currentTime + step, 0), app.player.trackDuration))
            }
        }
        .frame(height: 18)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard app.player.trackDuration > 0, width > 0 else { return }
                let ratio = min(max(value.location.x / width, 0), 1)
                dragProgress = ratio
                app.player.beginScrub()
                app.player.scrub(to: ratio * duration)
            }
            .onEnded { _ in
                guard let dragProgress, app.player.trackDuration > 0 else { return }
                app.player.endScrub(at: dragProgress * duration)
                self.dragProgress = nil
            }
    }
}

/// Apple Music-style 0–5 star rating control. Shows the song's rating; clicking
/// a star sets it (re-clicking the current star clears it). `app` is passed
/// explicitly: no `@Environment` here, because this view is also rendered inside
/// `Table` cells, which don't reliably inherit the SwiftUI environment.
///
/// Hover preview is computed from the continuous cursor position across the
/// whole control, so the visual gap between glyphs can't reset it (per-glyph
/// `onHover` fired leave→enter across each gap and flickered the fill).
/// Click hitboxes reach into the gap too — each button pads into the space
/// shared with its neighbor.
struct RatingStars: View {
    let song: SubsonicSong
    let app: AppState
    var size: CGFloat = 14
    var spacing: CGFloat = 3

    @State private var hoveredStar: Int?
    @State private var trackWidth: CGFloat = 0

    private var rating: Int { app.effectiveRating(for: song) }
    private var displayRating: Int { hoveredStar ?? rating }
    private var estimatedWidth: CGFloat { (size + spacing) * 5 }
    private var effectiveTrackWidth: CGFloat { trackWidth > 0 ? trackWidth : estimatedWidth }

    var body: some View {
        let content = HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let target = star == rating ? 0 : star
                    app.setRating(target, for: song)
                } label: {
                    Image(systemName: star <= displayRating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(star <= displayRating ? Color.yellow : Color.secondary)
                        .padding(.horizontal, spacing / 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.format("format.rating.rate", star))
                .accessibilityLabel(L10n.format("format.rating.rate", star))
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let slot = effectiveTrackWidth / 5
                let newStar = slot > 0 ? min(5, max(1, Int(point.x / slot) + 1)) : nil
                // Write ONLY on an actual star change: onContinuousHover
                // fires per mouse-move event (60–120 Hz even inside one
                // glyph), and every redundant @State write invalidates and
                // re-renders the control — flooding the main actor and
                // delaying the click's own render behind the flood.
                if newStar != hoveredStar { hoveredStar = newStar }
            case .ended:
                if hoveredStar != nil { hoveredStar = nil }
            @unknown default:
                break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Рейтинг".localized)
        .accessibilityValue(L10n.format("format.rating.outOfFive", rating))
        .contentShape(Rectangle())

        if size > 10 {
            content.onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                trackWidth = $0
            }
        } else {
            content
        }
    }
}

/// Ellipsis action button triggering the song context menu.
struct SongEllipsisMenu: View {
    let song: SubsonicSong
    var foregroundStyle: Color = .secondary
    var app: AppState?
    var extraActions: [SongMenuExtraAction] = []
    var compact: Bool = false
    var side: CGFloat?

    @Environment(AppState.self) private var envApp: AppState?

    private var resolvedApp: AppState? {
        app ?? envApp
    }

    private var resolvedSide: CGFloat {
        if let side { return side }
        return compact ? 22 : 28
    }

    var body: some View {
        let button = Button {
            if let resolvedApp {
                showSongActionMenu(
                    for: song,
                    app: resolvedApp,
                    selection: [song],
                    extraActions: extraActions
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: (resolvedSide <= 16) ? 10 : (compact ? 12 : 14), weight: .semibold))
                .foregroundStyle(foregroundStyle)
        }
        .buttonStyle(.plain)
        .frame(width: resolvedSide, height: resolvedSide)
        .contentShape(Rectangle())
        .help("Ещё".localized)
        .accessibilityLabel("Действия для песни".localized)

        if compact {
            button
        } else {
            button.hoverBrighten()
        }
    }
}

/// Apple Music-style capsule action button (Play / Shuffle / Add) with hover feedback.
/// Shared by the album and playlist detail pages.
struct ActionPill: View {
    let title: String
    let systemImage: String
    let filled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ActionPillLabel(title: title, systemImage: systemImage, filled: filled, hovering: hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .accessibilityLabel(title.localized)
    }
}

/// The capsule-styled glyph+text used inside `ActionPill`, also usable as a
/// `Menu` label so a pill can offer a dropdown (e.g. the album "Добавить").
struct ActionPillLabel: View {
    let title: String
    let systemImage: String
    let filled: Bool
    var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 12))
            Text(title.localized).font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(fillColor))
        .overlay(Capsule().strokeBorder(filled ? Color.clear : Color.secondary.opacity(0.5)))
        .foregroundStyle(filled ? .white : Color.primary)
        .animation(.snappy(duration: 0.15), value: hovering)
    }

    private var fillColor: Color {
        if filled { return AMColor.accent }
        return hovering ? AMColor.surfaceLight : Color.clear
    }
}

/// Round favorite button matching RoundEllipsisMenu for detail-page action rows.
struct RoundFavoriteButton: View {
    let isStarred: Bool
    var size: CGFloat = 32
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hovering ? AMColor.surfaceTertiaryHover : AMColor.surfaceLight)

                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(isStarred ? AMColor.accent : Color.secondary)
            }
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .help(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
        .accessibilityLabel(isStarred ? "Убрать из избранного".localized : "В избранное".localized)
    }
}
