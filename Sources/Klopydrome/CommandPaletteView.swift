import SwiftUI
import NavidromeClient

enum CommandPaletteGroup: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case actions = "Actions"
    case playlists = "Playlists"
    case search = "Search Results"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .navigation: return "Sections".localized
        case .actions: return "Actions".localized
        case .playlists: return "Playlists".localized
        case .search: return "Search Results".localized
        }
    }
}

struct CommandPaletteItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let coverArt: String?
    let group: CommandPaletteGroup
    let action: () -> Void

    static func == (lhs: CommandPaletteItem, rhs: CommandPaletteItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct CommandPaletteView: View {
    let onDismiss: () -> Void
    @Environment(AppState.self) var app

    @State var query = ""
    @State var highlightedIndex = 0
    @State var remoteResults: [CommandPaletteItem] = []
    @State var isSearchingRemote = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .frame(width: 580)
        .frame(maxHeight: 440)
        .onAppear {
            isTextFieldFocused = true
            highlightedIndex = 0
        }
        .task(id: query) {
            await handleQueryChanged(query)
        }
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            executeHighlighted()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }
}

// MARK: - Subviews

extension CommandPaletteView {
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AMColor.secondaryText)

            TextField("Search or jump to…".localized, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .focused($isTextFieldFocused)

            if isSearchingRemote {
                ProgressView()
                    .controlSize(.small)
            }

            Text("esc")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(AMColor.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if allItems.isEmpty {
                        emptyState
                    } else {
                        itemsSections(proxy: proxy)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing Found".localized,
            systemImage: "magnifyingglass",
            description: Text("Try searching with another query.".localized)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func itemsSections(proxy: ScrollViewProxy) -> some View {
        let items = allItems
        ForEach(CommandPaletteGroup.allCases) { group in
            let groupItems = items.filter { $0.group == group }
            if !groupItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AMColor.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                    ForEach(groupItems) { item in
                        let idx = items.firstIndex(of: item) ?? 0
                        rowView(for: item, isHighlighted: idx == highlightedIndex)
                            .id(item.id)
                            .onTapGesture {
                                execute(item)
                            }
                    }
                }
            }
        }
        .onChange(of: highlightedIndex) { _, newIndex in
            if newIndex >= 0 && newIndex < items.count {
                withAnimation(.snappy(duration: 0.15)) {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private func rowView(for item: CommandPaletteItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            rowIcon(for: item)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(AMFont.rowTitle)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isHighlighted {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AMColor.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AMColor.sidebarSelection.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowIcon(for item: CommandPaletteItem) -> some View {
        if let coverArt = item.coverArt, !coverArt.isEmpty {
            CoverArtView(coverArt: coverArt, size: 24, cornerRadius: 4)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AMColor.secondaryText)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }
}

// MARK: - Logic & Search

extension CommandPaletteView {
    var allItems: [CommandPaletteItem] {
        filteredLocalItems + remoteResults
    }

    private var filteredLocalItems: [CommandPaletteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !trimmed.isEmpty else {
            return localItems
        }
        return localItems.filter {
            $0.title.localizedLowercase.contains(trimmed) ||
            ($0.subtitle?.localizedLowercase.contains(trimmed) ?? false)
        }
    }

    private func moveHighlight(by delta: Int) {
        let items = allItems
        guard !items.isEmpty else { return }
        let next = highlightedIndex + delta
        if next < 0 {
            highlightedIndex = items.count - 1
        } else if next >= items.count {
            highlightedIndex = 0
        } else {
            highlightedIndex = next
        }
    }

    private func executeHighlighted() {
        let items = allItems
        guard highlightedIndex >= 0 && highlightedIndex < items.count else { return }
        execute(items[highlightedIndex])
    }

    private func execute(_ item: CommandPaletteItem) {
        onDismiss()
        item.action()
    }

    func handleQueryChanged(_ newQuery: String) async {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        highlightedIndex = 0
        guard trimmed.count >= 2, app.isConnected, !app.isOfflineSession else {
            remoteResults = []
            return
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
            return
        }

        isSearchingRemote = true
        defer { isSearchingRemote = false }

        await performRemoteSearch(trimmed)
    }

    private func performRemoteSearch(_ trimmed: String) async {
        guard let client = app.client else { return }
        do {
            let res = try await client.search3(query: trimmed, artistCount: 5, albumCount: 5, songCount: 5)
            guard !Task.isCancelled else { return }
            var results: [CommandPaletteItem] = []

            for song in res.songs.prefix(5) {
                results.append(CommandPaletteItem(
                    id: "remote_song_\(song.id)",
                    title: song.displayTitle,
                    subtitle: song.artist,
                    icon: "music.note",
                    coverArt: song.coverArt,
                    group: .search,
                    action: { [weak app] in
                        app?.play([song], at: 0)
                    }
                ))
            }

            for album in res.albums.prefix(5) {
                results.append(CommandPaletteItem(
                    id: "remote_album_\(album.id)",
                    title: album.title ?? album.album ?? album.name ?? "Untitled",
                    subtitle: album.artist,
                    icon: "square.stack",
                    coverArt: album.coverArt,
                    group: .search,
                    action: { [weak app] in
                        app?.openAlbumInLibrary(album)
                    }
                ))
            }

            for artist in res.artists.prefix(5) {
                results.append(CommandPaletteItem(
                    id: "remote_artist_\(artist.id)",
                    title: artist.name,
                    subtitle: "Artist".localized,
                    icon: "music.mic",
                    coverArt: artist.coverArt,
                    group: .search,
                    action: { [weak app] in
                        app?.openArtistInLibrary(artist)
                    }
                ))
            }

            remoteResults = results
        } catch {
            remoteResults = []
        }
    }
}
