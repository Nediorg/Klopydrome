import SwiftUI
import NavidromeClient

/// Observes horizontal scroll offset of the enclosing NSScrollView in real time.
private struct HorizontalScrollObserver: NSViewRepresentable {
    @Binding var scrollX: CGFloat

    func makeNSView(context: Context) -> ScrollObserverView {
        let view = ScrollObserverView()
        view.onScroll = { offset in
            if abs(self.scrollX - offset) > 0.5 {
                self.scrollX = offset
            }
        }
        return view
    }

    func updateNSView(_ nsView: ScrollObserverView, context: Context) {
        nsView.onScroll = { offset in
            if abs(self.scrollX - offset) > 0.5 {
                self.scrollX = offset
            }
        }
    }

    final class ScrollObserverView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var notificationObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            setupObserver()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            setupObserver()
        }

        private func setupObserver() {
            if let existing = notificationObserver {
                NotificationCenter.default.removeObserver(existing)
                notificationObserver = nil
            }
            guard let clipView = enclosingScrollView?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true
            notificationObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let clip = self.enclosingScrollView?.contentView else { return }
                self.onScroll?(clip.bounds.origin.x)
            }
            onScroll?(clipView.bounds.origin.x)
        }

        deinit {
            if let existing = notificationObserver {
                NotificationCenter.default.removeObserver(existing)
            }
        }
    }
}

/// A combined single-line horizontal carousel for "Latest Release" and "Top Songs",
/// matching Apple Music Sequoia.
///
/// When scrolled horizontally, the "Latest Release" scrolls out of view while the
/// "Top Songs" header smoothly docks at the leading edge and stays pinned there.
struct ArtistHeroRow: View {
    let artist: Artist
    let latest: SubsonicAlbum?
    let top: [SubsonicSong]?

    @Environment(AppState.self) private var app
    @State private var scrollX: CGFloat = 0
    @State private var latestWidth: CGFloat = 314
    @State private var releaseHovered = false

    private let interSectionSpacing: CGFloat = 24

    private var hasLatest: Bool { latest != nil }
    private var hasTop: Bool { top != nil && top?.isEmpty == false }

    /// Calculates the horizontal offset needed to dock the header at the left edge
    /// once the user scrolls into the Top Songs section.
    private var dockOffset: CGFloat {
        guard hasLatest else { return max(0, scrollX) }
        let startX = latestWidth + interSectionSpacing
        let rawOffset = max(0, scrollX - startX)
        let columnsCount = CompactSongItem.columns(from: top ?? []).count
        let totalWidth = CGFloat(columnsCount) * (280 + 16)
        let maxOffset = max(0, totalWidth - 160)
        return min(rawOffset, maxOffset)
    }

    var body: some View {
        if hasLatest || hasTop {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: interSectionSpacing) {
                    if let latest {
                        latestReleaseItem(latest)
                    }
                    if let top, !top.isEmpty {
                        topSongsCarousel(top)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(HorizontalScrollObserver(scrollX: $scrollX))
            }
            .scrollClipDisabled()
        }
    }

    private let coverSize: CGFloat = 150

    private func latestReleaseItem(_ latest: SubsonicAlbum) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последний релиз".localized)
                .font(.title2.bold())
            Button {
                app.openAlbumInLibrary(latest)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    CoverArtView(coverArt: latest.coverArt, size: coverSize, shadow: true)
                    VStack(alignment: .leading, spacing: 4) {
                        if let year = latest.year {
                            Text(String(year))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AMColor.secondaryText)
                        }
                        Text(latest.displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let count = latest.songCount {
                            Text("\(count) \(Pluralized.song(count))")
                                .font(.caption)
                                .foregroundStyle(AMColor.secondaryText)
                        } else {
                            Text(latest.artist ?? artist.name)
                                .font(.caption)
                                .foregroundStyle(AMColor.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: coverSize, alignment: .leading)
                }
                .contentShape(Rectangle())
                .brightness(releaseHovered ? 0.08 : 0)
                .animation(.snappy(duration: 0.15), value: releaseHovered)
            }
            .buttonStyle(.plain)
            .onHover { releaseHovered = $0 }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { latestWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in latestWidth = newWidth }
            }
        )
    }

    private func topSongsCarousel(_ top: [SubsonicSong]) -> some View {
        let columns = CompactSongItem.columns(from: top)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Лучшие песни".localized)
                    .font(.title2.bold())
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .offset(x: dockOffset)
            .zIndex(1)

            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, colItems in
                    CompactSongColumn(
                        items: colItems,
                        allSongs: top,
                        subtitle: { song in
                            let yearStr = song.year.map(String.init)
                            let parts = [song.album, yearStr].compactMap { $0 }.filter { !$0.isEmpty }
                            return parts.isEmpty ? (song.artist ?? "") : parts.joined(separator: " · ")
                        }
                    )
                    .frame(width: 280)
                }
            }
        }
    }
}
