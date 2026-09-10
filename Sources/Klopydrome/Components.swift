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

/// Subtle scale on hover for card-like tappables (Apple Music style).
struct HoverScale: ViewModifier {
    @State private var hovering = false
    var amount: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1)
            .zIndex(hovering ? 1 : 0)
            .animation(Motion.spring(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverScale(_ amount: CGFloat = 1.02) -> some View {
        modifier(HoverScale(amount: amount))
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
            .accessibilityLabel("Позиция воспроизведения")
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

    var body: some View {
        HStack(spacing: 0) {
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
                let slot = trackWidth / 5
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            trackWidth = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Рейтинг")
        .accessibilityValue(L10n.format("format.rating.outOfFive", rating))
        .contentShape(Rectangle())
    }
}

/// A song row styled like the Music app's track list. The currently playing row
/// gets a solid red background with white text (Apple Music behaviour).

/// Sort criteria for album grids — unified with the artist page (10 topics).
/// Server-driven cases keep pagination globally sorted; local cases sort the
/// already-fetched pages client-side (used for Songs and for album sorts
/// without a server `AlbumListType`).
enum LibrarySort: String, CaseIterable, Hashable, Identifiable {
    case release, name, popularity, recentlyAdded, artist, duration, playCount, genre, favorite, id
    var id: String { rawValue }
    var label: String {
        switch self {
        case .release: return "По дате релиза"
        case .name: return "По названию"
        case .popularity: return "По популярности"
        case .recentlyAdded: return "По дате добавления"
        case .artist: return "По исполнителю"
        case .duration: return "По длительности"
        case .playCount: return "По прослушиваниям"
        case .genre: return "По жанру"
        case .favorite: return "По избранным"
        case .id: return "По ID"
        }
    }

    /// Server type for globally sorted pagination, or `nil` when the sort
    /// must be applied locally (e.g. duration, genre, ID).
    var asAlbumListType: AlbumListType? {
        switch self {
        case .name: return .alphabeticalByName
        case .artist: return .alphabeticalByArtist
        case .recentlyAdded: return .newest
        case .popularity, .playCount: return .frequent
        case .favorite: return .starred
        case .release, .duration, .genre, .id: return nil
        }
    }

    /// Maps to the artist-page `ArtistAlbumSort` for the shared local sorter.
    var asArtistAlbumSort: ArtistAlbumSort {
        switch self {
        case .release: return .release
        case .name: return .name
        case .popularity: return .popularity
        case .recentlyAdded: return .recentlyAdded
        case .artist: return .artist
        case .duration: return .duration
        case .playCount: return .playCount
        case .genre: return .genre
        case .favorite: return .favorite
        case .id: return .id
        }
    }
}

/// Library section header: centered title, a donut menu (caller-provided
/// filter options) and a filter button that expands into an inline search
/// field on the same row. Shared by the album grids and the Songs table.
struct SongEllipsisMenu: View {
    let song: SubsonicSong
    var foregroundStyle: Color = .secondary
    var extraMenuItems: (() -> AnyView)?

    @Environment(AppState.self) private var app

    var body: some View {
        Menu {
            if let extraMenuItems { extraMenuItems() }
            SongActionItems(app: app, song: song, selection: [song])
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(foregroundStyle)
        .help("Ещё")
        .accessibilityLabel("Действия для песни")
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
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.15), value: hovering)
    }

    private var fillColor: Color {
        if filled { return AMColor.accent }
        return hovering ? AMColor.surfaceLight : Color.clear
    }
}

/// Round "…" menu button for detail-page action rows (album, playlists). Per the
/// Apple Music button bar: a square hit target with the glyph centered on an
/// elevated circular surface, glyph tinted with the accent.
struct RoundEllipsisMenu<MenuContent: View>: View {
    @ViewBuilder let content: MenuContent
    var size: CGFloat = 32

    @State private var hovering = false

    var body: some View {
        Menu {
            content
        } label: {
            ZStack {
                // 1. The strict background layer
                Circle()
                    .fill(hovering ? AMColor.surfaceTertiaryHover : AMColor.surfaceLight)
                    .frame(width: size, height: size)

                // 2. The icon layer
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AMColor.accent)
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Ещё")
        .help("Ещё")
    }
}
