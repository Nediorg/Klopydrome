import SwiftUI
import NavidromeClient

/// Apple Music-style "Listen Now": a few horizontally scrolling shelves of
/// large album cards.
struct HomeView: View {
    @Environment(AppState.self) private var app

    enum Shelf: String, CaseIterable, Identifiable {
        case new = "Новые релизы"
        case recent = "Недавно добавленные"
        case random = "Для вас"
        case frequent = "Частое"

        var listType: AlbumListType {
            switch self {
            case .new: return .newest
            case .recent: return .recent
            case .random: return .random
            case .frequent: return .frequent
            }
        }
        var id: String { rawValue }
    }

    @State private var loading = true
    @State private var loadingShelves: Set<Shelf> = []

    private var errorsByShelf: [Shelf: String] {
        var dict: [Shelf: String] = [:]
        for shelf in Shelf.allCases {
            if let err = app.library.homeShelfErrors[shelf.listType] {
                dict[shelf] = err
            }
        }
        return dict
    }

    private var albumsByShelf: [Shelf: [SubsonicAlbum]] {
        var dict: [Shelf: [SubsonicAlbum]] = [:]
        for shelf in Shelf.allCases {
            dict[shelf] = app.library.homeShelves[shelf.listType] ?? []
        }
        return dict
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 32) {
                if loading && albumsByShelf.isEmpty && loadingShelves.isEmpty {
                    ProgressView("Загружаем библиотеку…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    ForEach(Shelf.allCases) { shelf in
                        albumShelf(shelf)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollClipDisabled()
        .refreshable { await load() }
        .task(id: app.client != nil) { await loadIfNeeded() }
    }

    private func shelfHeader(_ shelf: Shelf) -> some View {
        HStack(spacing: 6) {
            Text(shelf.rawValue)
                .font(.title2.bold())
            Spacer()
            if loadingShelves.contains(shelf) {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await reloadShelf(shelf) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(minWidth: 30, minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AMColor.accent)
            .hoverBrighten()
            .accessibilityLabel("Обновить")
            .help("Обновить")
        }
    }

    @ViewBuilder
    private func shelfContent(_ shelf: Shelf) -> some View {
        let albums = albumsByShelf[shelf] ?? []
        if loadingShelves.contains(shelf) {
            ForEach(0..<6, id: \.self) { _ in AlbumCardPlaceholder() }
        } else if let error = errorsByShelf[shelf] {
            retryRow(shelf, error: error)
        } else {
            ForEach(albums) { album in
                NavigationLink(value: album) {
                    AlbumCard(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func albumShelf(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            shelfHeader(shelf)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    shelfContent(shelf)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func retryRow(_ shelf: Shelf, error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Не удалось загрузить".localized)
                .font(.callout.weight(.semibold))
            Text(error)
                .font(.caption)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(2)
            Button("Повторить") {
                Task { await reloadShelf(shelf) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(width: 220, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AMColor.surface))
    }

    /// Loads every shelf only when the home store has never been fetched, so a
    /// revisit to the tab shows instant cached shelves. Repeated appearances
    /// don't re-fetch; pull-to-refresh / the per-shelf arrow still force a
    /// reload. If shelves are empty (failed load), allow re-fetch.
    private func loadIfNeeded() async {
        let hasAnyData = Shelf.allCases.contains { shelf in
            !(app.library.homeShelves[shelf.listType] ?? []).isEmpty
        }
        guard !app.library.homeShelvesLoaded || !hasAnyData else {
            loading = false
            loadingShelves.removeAll()
            return
        }
        await load()
    }

    private func load() async {
        guard let client = app.client else {
            loading = false
            return
        }
        if app.library.homeShelves.isEmpty { loading = true }
        loadingShelves = Set(Shelf.allCases)
        defer {
            loading = false
            loadingShelves.removeAll()
        }
        await withTaskGroup(of: (Shelf, [SubsonicAlbum], String?).self) { group in
            for shelf in Shelf.allCases {
                group.addTask {
                    do {
                        let albums = try await client.getAlbumList2(type: shelf.listType, size: 24)
                        return (shelf, albums, nil)
                    } catch {
                        if error is CancellationError { return (shelf, [], nil) }
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                            return (shelf, [], nil)
                        }
                        return (shelf, [], error.localizedDescription)
                    }
                }
            }
            var anySuccess = false
            for await (shelf, albums, error) in group {
                if albums.isEmpty, error == nil { continue }
                app.library.homeShelves[shelf.listType] = albums
                app.library.homeShelfErrors[shelf.listType] = error
                if !albums.isEmpty { anySuccess = true }
            }
            app.library.homeShelvesLoaded = anySuccess || !app.library.homeShelvesLoaded
        }
    }

    private func reloadShelf(_ shelf: Shelf) async {
        guard let client = app.client else { return }
        loadingShelves.insert(shelf)
        defer { loadingShelves.remove(shelf) }
        do {
            app.library.homeShelves[shelf.listType] = try await client.getAlbumList2(type: shelf.listType, size: 24)
            app.library.homeShelfErrors[shelf.listType] = nil
        } catch {
            if error is CancellationError { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            app.library.homeShelfErrors[shelf.listType] = error.localizedDescription
        }
    }
}

struct AlbumCard: View {
    let album: SubsonicAlbum
    var width: CGFloat = 165
    var showsArtist: Bool = true
    /// When true, the release year is shown under the artist line — useful on
    /// discography surfaces (artist page); most grids keep the card compact.
    var showsYear: Bool = false
    /// Reserves room for a two-line title so every card is the same height and
    /// grid rows stay uniform (re-sorting never shifts the layout). The spare
    /// space lands at the bottom of the card — the text block stays compact.
    /// Opt-in: most surfaces prefer cards that hug their content.
    var reservesTitleLines: Bool = false

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var isStarred: Bool { app.isStarred(album) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                CoverArtView(coverArt: album.coverArt, size: width, cornerRadius: 8, shadow: true)
                    .scaleEffect(hovering ? 1.02 : 1)
                    .animation(.snappy(duration: 0.15), value: hovering)
                textBlock
            }
            .frame(width: width, alignment: .leading)
            .foregroundStyle(.primary)

            if hovering {
                Button {
                    app.toggleStar(album)
                } label: {
                    Image(systemName: isStarred ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(isStarred ? AMColor.accent : .white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(isStarred ? "Убрать из избранного" : "В избранное")
                .accessibilityLabel(isStarred ? "Убрать альбом из избранного" : "Добавить альбом в избранное")
                .transition(.opacity)
            }
        }
        .zIndex(hovering ? 1 : 0)
        .animation(.snappy(duration: 0.15), value: isStarred)
        .onHover { hovering = $0 }
        .accessibilityLabel(album.displayName)
        .accessibilityAction(named: isStarred ? "Убрать из избранного" : "В избранное") {
            app.toggleStar(album)
        }
        .contextMenu {
            AlbumContextMenuItems(album: album)
        }
    }
}

private extension AlbumCard {
    /// Title/artist/year block. With `reservesTitleLines` a hidden twin (two
    /// title lines + artist + year) sets the block's height so all cards are
    /// equal; the real text overlays it top-aligned, so a short title leaves
    /// the spare space at the bottom of the card, not between the title and
    /// the artist. Without the flag the block hugs its content.
    @ViewBuilder
    var textBlock: some View {
        if reservesTitleLines {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Название\nальбома".localized)
                        .font(.callout)
                        .lineLimit(2)
                    if showsArtist {
                        Text("Исполнитель".localized).font(.callout)
                    }
                    if showsYear {
                        Text("0000").font(.callout)
                    }
                }
                .hidden()
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    titleLine
                    artistLine
                    yearLine
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                titleLine
                artistLine
                yearLine
            }
        }
    }

    private var titleLine: some View {
        Text(album.displayName)
            .font(.callout)
            .lineLimit(2)
    }

    @ViewBuilder
    private var artistLine: some View {
        if showsArtist {
            Text(album.artist ?? "")
                .font(.callout)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var yearLine: some View {
        if showsYear, let year = album.year {
            Text(String(year))
                .font(.callout)
                .foregroundStyle(AMColor.secondaryText)
                .lineLimit(1)
        }
    }
}

struct AlbumCardPlaceholder: View {
    var width: CGFloat = 165

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: width)
            Text("Album Name")
                .font(.callout)
                .redacted(reason: .placeholder)
            Text("Artist")
                .font(.caption)
                .redacted(reason: .placeholder)
        }
        .frame(width: width, alignment: .leading)
    }
}