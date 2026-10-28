import SwiftUI

struct LibraryHeader<MenuContent: View>: View {
    let title: String
    @Binding var searchText: String
    var isLoading: Bool = false
    var filteredCount: Int?
    var totalCount: Int?
    private var isSearchExpanded: Binding<Bool>?
    @ViewBuilder let menuContent: MenuContent

    @State private var internalSearchVisible = false
    @FocusState private var searchFocused: Bool

    private var searchVisible: Bool {
        get { (isSearchExpanded ?? $internalSearchVisible).wrappedValue }
        nonmutating set { (isSearchExpanded ?? $internalSearchVisible).wrappedValue = newValue }
    }

    init(
        title: String,
        searchText: Binding<String>,
        isLoading: Bool = false,
        filteredCount: Int? = nil,
        totalCount: Int? = nil,
        isSearchExpanded: Binding<Bool>? = nil,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self._searchText = searchText
        self.isLoading = isLoading
        self.filteredCount = filteredCount
        self.totalCount = totalCount
        self.isSearchExpanded = isSearchExpanded
        self.menuContent = menuContent()
    }

    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title.localized)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 90)
                    .opacity(searchVisible ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: searchVisible)
            }

            HStack(spacing: 8) {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                        .transition(.opacity)
                        .help("Loading".localized)
                        .accessibilityLabel("Loading".localized)
                }
                if searchVisible {
                    searchFieldInput
                }

                searchToggleButton

                if MenuContent.self != EmptyView.self {
                    Menu {
                        menuContent
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .tint(Color.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .help("Settings".localized)
                    .accessibilityLabel("Settings".localized)
                }
            }
        }
        .frame(minHeight: 34)
        .padding(4)
        .onAppear {
            if !searchText.isEmpty {
                searchVisible = true
            }
        }
        .background {
            Button("") {
                withAnimation(Motion.spring(Motion.expand)) {
                    searchVisible = true
                }
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private var searchToggleButton: some View {
        Button {
            withAnimation(Motion.spring(Motion.expand)) {
                if searchVisible {
                    searchText = ""
                    searchVisible = false
                } else {
                    searchVisible = true
                }
            }
            if searchVisible {
                searchFocused = true
            }
        } label: {
            Image(systemName: searchVisible ? "xmark.circle.fill" : "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .hoverBrighten()
        .help(searchVisible ? "Close Search".localized : "Search".localized)
        .accessibilityLabel(searchVisible ? "Close Search".localized : "Search".localized)
        .animation(nil, value: searchVisible)
    }

    private var searchFieldInput: some View {
        HStack(spacing: 6) {
            if let filteredCount, let totalCount, !searchText.isEmpty {
                Text(L10n.format("format.filter.count", filteredCount, totalCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 2)
            }

            TextField("Search".localized, text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .controlSize(.small)
                .frame(width: 170)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .onSubmit { searchFocused = false }
                .onExitCommand {
                    withAnimation(Motion.spring(Motion.expand)) {
                        searchText = ""
                        searchVisible = false
                    }
                }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
        .clipped()
    }
}

extension LibraryHeader where MenuContent == EmptyView {
    init(
        title: String = "",
        searchText: Binding<String>,
        isLoading: Bool = false,
        filteredCount: Int? = nil,
        totalCount: Int? = nil,
        isSearchExpanded: Binding<Bool>? = nil
    ) {
        self.init(
            title: title,
            searchText: searchText,
            isLoading: isLoading,
            filteredCount: filteredCount,
            totalCount: totalCount,
            isSearchExpanded: isSearchExpanded,
            menuContent: { EmptyView() }
        )
    }
}
