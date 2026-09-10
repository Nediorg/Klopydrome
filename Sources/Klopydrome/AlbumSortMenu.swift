import SwiftUI

/// The artist-page album sort control: one pill holding the native sort-key
/// menu and the direction toggle, split by a divider — `[ Дата релиза | ↓ ]`.
/// The key selector stays a real `Menu` (fast native pull-down). A borderless
/// Menu ignores padding inside its label, so the padding lives on the Menu
/// view itself, and contentShape makes the padded background the hit target.
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
            // The app-wide accent tint is red; a borderless Menu paints its
            // label with the tint, so scope a neutral one to keep it white.
            .tint(.primary)
            .help("Сортировка альбомов")
            .accessibilityLabel("Сортировка альбомов")

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
        case .release: key = descending ? "Сначала новые" : "Сначала старые"
        case .name: key = descending ? "Сначала Я-А" : "Сначала А-Я"
        case .popularity: key = descending ? "Сначала популярные" : "Сначала непопулярные"
        case .recentlyAdded: key = descending ? "Сначала недавно добавленные" : "Сначала давно добавленные"
        case .artist: key = descending ? "Сначала Я-А" : "Сначала А-Я"
        case .duration: key = descending ? "Сначала длинные" : "Сначала короткие"
        case .playCount: key = descending ? "Сначала чаще слушаемые" : "Сначала реже слушаемые"
        case .genre: key = descending ? "Сначала Я-А" : "Сначала А-Я"
        case .favorite: key = descending ? "Сначала избранные" : "Сначала неизбранные"
        case .id: key = descending ? "По убыванию ID" : "По возрастанию ID"
        }
        return key.localized
    }
}
