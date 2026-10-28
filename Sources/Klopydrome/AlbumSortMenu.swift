import SwiftUI

struct AlbumSortMenu: View {
    @Binding var sort: ArtistAlbumSort
    @Binding var descending: Bool

    var body: some View {
        HStack(spacing: 1) {
            Menu {
                ForEach(ArtistAlbumSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.label.localized, systemImage: "checkmark")
                        } else {
                            Text(option.label.localized)
                        }
                    }
                }
            } label: {
                Text(sort.label.localized)
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .tint(.primary)
            .help("Album sorting".localized)
            .accessibilityLabel("Album sorting".localized)

            Rectangle()
                .fill(.primary.opacity(0.12))
                .frame(width: 1, height: 14)

            Button {
                descending.toggle()
            } label: {
                Image(systemName: descending ? "arrow.down" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(directionHelp)
            .accessibilityLabel(directionHelp)
        }
        .foregroundStyle(.primary)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }

    private var directionHelp: String {
        let key: String
        switch sort {
        case .release: key = descending ? "Newest first" : "Oldest first"
        case .name: key = descending ? "Z-A First" : "A-Z First"
        case .popularity: key = descending ? "Most popular first" : "Least popular first"
        case .recentlyAdded: key = descending ? "Recently Added First" : "Oldest Added First"
        case .artist: key = descending ? "Z-A First" : "A-Z First"
        case .duration: key = descending ? "Longest First" : "Shortest First"
        case .playCount: key = descending ? "Most played first" : "Least played first"
        case .genre: key = descending ? "Z-A First" : "A-Z First"
        case .favorite: key = descending ? "Favorites First" : "Non-Favorites First"
        case .id: key = descending ? "By ID (descending)" : "By ID (ascending)"
        }
        return key.localized
    }
}
