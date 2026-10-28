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
                    // Keep clear of the inline search field / menu cluster at the edges.
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
                        .help("Загрузка".localized)
                        .accessibilityLabel("Загрузка".localized)
                }
                // Inline search field appears on the right of the header,
                // replacing the magnifier button; the sort menu shifts to the
                // far right.
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
                    .help("Параметры".localized)
                    .accessibilityLabel("Параметры".localized)
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
            // Global Cmd+F keyboard shortcut trigger
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

    /// Static search/cancel button that stays fixed in place without sliding animation.
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
        .help(searchVisible ? "Закрыть поиск".localized : "Поиск".localized)
        .accessibilityLabel(searchVisible ? "Закрыть поиск".localized : "Поиск".localized)
        .animation(nil, value: searchVisible)
    }

    /// Inline search field; slides out with a clipping mask to the left of the static toggle button.
    private var searchFieldInput: some View {
        HStack(spacing: 6) {
            if let filteredCount, let totalCount, !searchText.isEmpty {
                Text(L10n.format("format.filter.count", filteredCount, totalCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 2)
            }

            TextField("Поиск".localized, text: $searchText)
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
