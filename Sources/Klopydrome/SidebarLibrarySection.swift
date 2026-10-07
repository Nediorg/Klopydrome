import SwiftUI
import NavidromeClient

struct SidebarLibrarySection: View {
    @Environment(AppState.self) private var app
    let selection: SidebarView.Selection?
    let select: (SidebarView.Selection) -> Void

    @State private var isEditingLibrary = false
    @State private var isLibraryHeaderHovered = false

    var body: some View {
        Section {
            if isEditingLibrary {
                ForEach(NavigationState.customizableLibrarySections, id: \.self) { section in
                    libraryEditRow(section)
                }
            } else {
                ForEach(NavigationState.customizableLibrarySections, id: \.self) { section in
                    if app.nav.visibleLibrarySections.contains(section) {
                        libraryRow(section.title, section)
                    }
                }
            }
        } header: {
            librarySectionHeader
        }
    }

    private var librarySectionHeader: some View {
        HStack {
            Text("Медиатека".localized)
            Spacer()
            if isEditingLibrary {
                Button("Готово".localized) {
                    isEditingLibrary = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            } else if isLibraryHeaderHovered {
                Button("Править".localized) {
                    isEditingLibrary = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .onHover { isLibraryHeaderHovered = $0 }
    }

    private func libraryRow(_ text: String, _ section: NavigationState.Section) -> some View {
        let isSelected = selection == .section(section)
        return Button {
            select(.section(section))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 16, height: 16)
                Text(text.localized)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tag(SidebarView.Selection.section(section))
    }

    private func libraryEditRow(_ section: NavigationState.Section) -> some View {
        let isChecked = app.nav.visibleLibrarySections.contains(section)
        return Button {
            app.toggleLibrarySection(section)
        } label: {
            HStack(spacing: 6) {
                checkboxView(isChecked: isChecked)

                Image(systemName: section.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16, height: 16)

                Text(section.title)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func checkboxView(isChecked: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(isChecked ? Color.accentColor : Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(isChecked ? Color.clear : Color.primary.opacity(0.25), lineWidth: 1)
                )
                .frame(width: 14, height: 14)

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
    }
}
