import SwiftUI
import NavidromeClient

struct SongRow: View {
    let song: SubsonicSong
    let index: Int?
    let showAlbum: Bool
    /// When non-nil, overrides the environment-derived current-track check.
    /// Lets parents pass a snapshot and enables `Equatable` skipping when
    /// `AppState` ticks for unrelated reasons (progress, downloads).
    var isCurrentOverride: Bool?
    /// Surface-specific prefix items for the row's context menu (e.g. «Убрать
    /// из плейлиста»); the canonical `SongActionItems` always follow.
    var extraMenuItems: (() -> AnyView)?
    var onPlay: ((Int) -> Void)?

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isCurrent: Bool { isCurrentOverride ?? (app.player.currentSong?.id == song.id) }
    private var fgPrimary: Color { isCurrent ? .white : .primary }
    private var fgSecondary: Color { isCurrent ? .white.opacity(0.8) : .secondary }
    private var isDownloading: Bool { app.downloadingSongIDs.contains(song.id) }
    private var isCachedLocally: Bool { app.isCached(song) }

    var body: some View {
        SongRowEdgeLayout(spacing: 10) {
            leadingContent
            trailingContent
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AMColor.accent)
            } else if hovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
            }
        }
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay?(index ?? 0) }
        .contextMenu {
            if let extraMenuItems { extraMenuItems() }
            SongActionItems(
                app: app,
                song: song,
                selection: [song],
                onPlay: onPlay.map { play in { play(index ?? 0) } }
            )
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(spacing: 10) {
            if let index {
                ZStack {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(fgSecondary)
                        .opacity(isCurrent ? 0 : 1)
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, alignment: .trailing)
            }
            if showAlbum, let coverArt = song.coverArt {
                CoverArtView(coverArt: coverArt, size: 36)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(song.displayTitle)
                    .font(.callout)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(fgPrimary)
                    .lineLimit(1)
                if showAlbum {
                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                } else if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(fgSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        HStack(spacing: 10) {
            if isDownloading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16, height: 16)
                    .help("Загрузка…")
                    .accessibilityLabel("Загрузка")
            } else {
                Button {
                    if isCachedLocally {
                        Task { await app.removeFromCache(song) }
                    } else {
                        app.cacheSong(song)
                    }
                } label: {
                    Image(systemName: isCachedLocally ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isCachedLocally ? AMColor.accent : Color.secondary)
                        .symbolEffect(.bounce, value: isCachedLocally)
                }
                .buttonStyle(.plain)
                .help(isCachedLocally ? "Удалить загрузку" : "Загрузить")
                .accessibilityLabel(isCachedLocally ? "Удалить загрузку"
                                                    : (isDownloading ? "Загрузка" : "Загрузить"))
                .opacity(hovering || isCachedLocally ? 1 : 0)
                .allowsHitTesting(hovering || isCachedLocally)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .transition(.opacity)
                .accessibilityHidden(false)
            }
            RatingStars(song: song, app: app, size: 11, spacing: 2)
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(fgSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            SongEllipsisMenu(song: song, foregroundStyle: isCurrent ? .white : .secondary, extraMenuItems: extraMenuItems)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(.snappy(duration: 0.12), value: hovering)
                .accessibilityHidden(false)
        }
    }
}

private struct SongRowEdgeLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout CGFloat
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        // Cache trailing width — it depends only on the trailing content
        // (duration + stars + buttons), not on the proposed width, so it is
        // stable across the two layout passes (sizeThatFits + placeSubviews).
        if cache == 0 {
            cache = subviews[1].sizeThatFits(.unspecified).width
        }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let idealWidth = leading.width + spacing + cache
        let height = max(leading.height, subviews[1].sizeThatFits(.unspecified).height)
        return CGSize(width: max(proposal.width ?? idealWidth, idealWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout CGFloat
    ) {
        guard subviews.count == 2 else { return }
        if cache == 0 {
            cache = subviews[1].sizeThatFits(.unspecified).width
        }
        let leadingWidth = max(0, bounds.width - cache - spacing)
        let height = bounds.height

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: leadingWidth, height: height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(width: cache, height: height)
        )
    }

    func makeCache(subviews: Subviews) -> CGFloat { 0 }
    func updateCache(_ cache: inout CGFloat, subviews: Subviews) {
        // Invalidate when trailing content changes (e.g. rating, duration).
        cache = 0
    }
}
