import SwiftUI

// MARK: - Detail Scaffold Kit

/// Canonical building blocks for detail screens (AlbumDetailView, PlaylistDetailView, etc.).
/// Eliminates duplicated error states, retry banners, and empty screens across detail views.

/// Full-screen or section-level empty error state with a retry button.
struct DetailUnavailableView: View {
    var title: String = "Не удалось загрузить треки".localized
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Повторить".localized) {
                onRetry()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 60)
    }
}

/// Compact inline error notice with warning icon and retry action.
struct DetailInlineErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Повторить".localized) {
                onRetry()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
