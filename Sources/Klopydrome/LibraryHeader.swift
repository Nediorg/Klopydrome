import SwiftUI

struct LibraryHeader<MenuContent: View>: View {
    let title: String
    @Binding var searchText: String
    var isLoading: Bool = false
    @ViewBuilder let menuContent: MenuContent

    @State private var searchVisible = false
    @FocusState private var searchFocused: Bool

    init(title: String, searchText: Binding<String>, isLoading: Bool = false,
         @ViewBuilder menuContent: () -> MenuContent) {
        self.title = title
        self._searchText = searchText
        self.isLoading = isLoading
        self.menuContent = menuContent()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                // Keep clear of the inline search field / menu cluster at the edges.
                .padding(.horizontal, 90)

            HStack(spacing: 8) {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                        .transition(.opacity)
                        .help("Загрузка")
                        .accessibilityLabel("Загрузка")
                }
                // Inline search field appears on the right of the header,
                // replacing the magnifier button; the sort menu shifts to the
                // far right.
                if searchVisible {
                    searchField
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Button {
                        withAnimation(Motion.spring(Motion.expand)) {
                            searchVisible = true
                        }
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .hoverBrighten()
                    .help("Поиск")
                    .accessibilityLabel("Поиск")
                    .accessibilityHint("Раскрывает поле поиска")
                    .transition(.opacity)
                }
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
                .help("Параметры")
                .accessibilityLabel("Параметры")
            }
        }
        .frame(minHeight: 34)
        .padding(4)
    }

    /// Inline search field; its icon button collapses the row again.
    private var searchField: some View {
        HStack(spacing: 4) {
            TextField("Поиск", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .controlSize(.small)
                .frame(width: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08)))
                .onSubmit { searchFocused = false }
                .onExitCommand {
                    withAnimation(Motion.spring(Motion.expand)) {
                        searchText = ""
                        searchVisible = false
                    }
                }

            Button {
                withAnimation(Motion.spring(Motion.expand)) {
                    searchText = ""
                    searchVisible = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .hoverBrighten()
            .help("Закрыть поиск")
            .accessibilityLabel("Закрыть поиск")
        }
    }
}

/// Hover ellipsis ("…") that reveals the same canonical song actions as a
/// right-click, as an explicit hover-revealed button (Apple Music-style). All
/// items come from the shared `SongActionItems`.
