import SwiftUI
import NavidromeClient

// MARK: - PlaylistDetailView Error & Action Helpers

extension PlaylistDetailView {
    func emptyErrorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Не удалось загрузить треки".localized, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Повторить".localized) {
                app.loadPlaylistIfNeeded(playlist, forceReload: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 60)
    }

    func inlineErrorNotice(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Повторить".localized) {
                app.loadPlaylistIfNeeded(playlist, forceReload: true)
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

    func startPlayback(shuffled: Bool) async {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        if shuffled {
            await app.playShuffled(playlist)
        } else {
            await app.play(playlist)
        }
    }

    func remove(at index: Int, from detail: PlaylistDetail) {
        guard let client = app.client else { return }
        Task {
            try? await client.updatePlaylist(id: detail.id, removeIndexes: [index])
            app.invalidatePlaylistDetail(for: detail.id)
            app.loadPlaylistIfNeeded(playlist, forceReload: true)
        }
    }

    func delete(_ detail: PlaylistDetail) {
        guard let client = app.client else { return }
        Task {
            try? await client.deletePlaylist(id: detail.id)
            app.invalidatePlaylistDetail(for: detail.id)
            await app.refreshPlaylists()
        }
    }
}
