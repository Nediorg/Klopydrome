import SwiftUI
import NavidromeClient
import AppKit

enum Motion {
    static let hover = Animation.snappy(duration: 0.12, extraBounce: 0)
    static let expand = Animation.snappy(duration: 0.2, extraBounce: 0)
    static let feedback = Animation.snappy(duration: 0.15, extraBounce: 0.1)

    static var enabled: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func spring(_ base: Animation) -> Animation {
        enabled ? base : .linear(duration: 0)
    }
}

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

extension View {
    func emptyStatePinnedToTop(topPadding: CGFloat = 48) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, topPadding)
    }
}

struct SongMetadataGrid: View {
    let song: SubsonicSong

    private var rows: [(label: String, value: String?)] {
        [
            ("Album", song.album),
            ("Artist", song.artist),
            ("Album Artist", song.albumArtist),
            ("Year", song.year.map(String.init)),
            ("Genre", song.genre),
            ("Bitrate", song.bitRate.map { "\($0) kbps" }),
            ("Format", song.suffix?.uppercased()),
            ("Duration", song.duration.map { Player.format(seconds: Double($0)) }),
            ("Track Number", song.track.map(String.init)),
            ("Disc Number", song.discNumber.map(String.init)),
            ("Size", song.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }),
            ("Plays", song.playCount.map(String.init)),
            ("Path", song.path),
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

struct PlaybackSlider: View {
    @Environment(AppState.self) private var app

    var trackOpacity: Double = 0.15
    var progressColor: Color = AMColor.accent
    var progressOpacity: Double = 1

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
            .accessibilityLabel("Playback position".localized)
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
                if newStar != hoveredStar { hoveredStar = newStar }
            case .ended:
                if hoveredStar != nil { hoveredStar = nil }
            @unknown default:
                break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rating".localized)
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

struct SongEllipsisMenu: View {
    let song: SubsonicSong
    var selection: [SubsonicSong] = []
    var resolveSelection: (() -> [SubsonicSong])?
    var foregroundStyle: Color = .secondary
    var app: AppState?
    var playlist: PlaylistSummary?
    var playlistIndex: Int?
    var extraActions: [SongMenuExtraAction] = []
    var compact: Bool = false
    var side: CGFloat?

    @Environment(AppState.self) private var envApp: AppState?
    @State private var isHovering = false

    private var resolvedApp: AppState? {
        app ?? envApp
    }

    private var resolvedSide: CGFloat {
        if let side { return side }
        return compact ? 22 : 28
    }

    var body: some View {
        ZStack {
            Image(systemName: "ellipsis")
                .font(.system(size: (resolvedSide <= 16) ? 10 : (compact ? 12 : 14), weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .brightness(isHovering && !compact ? 0.14 : 0)

            EllipsisClickTrigger { event, view in
                guard let resolvedApp else { return }
                let targets: [SubsonicSong] = {
                    if let resolveSelection {
                        let resolved = resolveSelection()
                        return resolved.count > 1 ? resolved : [song]
                    }
                    return selection.isEmpty ? [song] : selection
                }()
                let menu = buildSongActionMenu(
                    for: song,
                    app: resolvedApp,
                    selection: targets,
                    playlist: playlist,
                    playlistIndex: playlistIndex,
                    extraActions: extraActions
                )
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        }
        .frame(width: resolvedSide, height: resolvedSide)
        .contentShape(Rectangle())
        .help("More".localized)
        .accessibilityLabel("Song Actions".localized)
        .onHover { hovering in
            if !compact {
                if hovering {
                    if !ScrollGate.shared.isScrolling {
                        isHovering = true
                    }
                } else if isHovering {
                    isHovering = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ScrollGate.scrollDidStart)) { _ in
            if isHovering {
                isHovering = false
            }
        }
    }
}

private struct EllipsisClickTrigger: NSViewRepresentable {
    var onMouseDown: (NSEvent, NSView) -> Void

    func makeNSView(context: Context) -> EllipsisClickNSView {
        let view = EllipsisClickNSView()
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ nsView: EllipsisClickNSView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }
}

private final class EllipsisClickNSView: NSView {
    var onMouseDown: ((NSEvent, NSView) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event, self)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown?(event, self)
    }
}

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

struct ActionPillLabel: View {
    let title: String
    let systemImage: String
    let filled: Bool
    var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage).font(AMFont.actionPillIcon)
            Text(title.localized).font(AMFont.actionPill)
        }
        .padding(.horizontal, 16)
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
        .help(isStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
        .accessibilityLabel(isStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
    }
}

struct EditRulesButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                    .font(.caption2.weight(.semibold))
                Text("Edit Rules".localized)
                    .font(.callout.bold())
            }
            .foregroundStyle(AMColor.accent)
            .brightness(hovered ? 0.15 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
