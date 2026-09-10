import SwiftUI
import NavidromeClient

/// The anchored toolbar popover (arrowed) listing offline downloads:
/// active transfers with live progress, the finished song list, and a
/// one-tap "download the current album" action. Read as a normal standalone
/// icon — separate from any one song's inline download affordance.
struct DownloadsPopoverView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !app.downloadingSongs.isEmpty {
                activeSection
                Divider()
            }

            if app.downloadedSongs.isEmpty {
                emptyState
            } else {
                downloadedSection
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Загрузки".localized)
                .font(.headline)
            Spacer()
            if app.nav.selectedPlaylist != nil {
                Button("Загрузить плейлист") { app.cacheCurrentPlaylist() }
                    .buttonStyle(.borderless)
            } else {
                Button("Загрузить альбом") { app.cacheCurrentAlbum() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Загрузка".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(app.downloadingSongs) { song in
                DownloadRow(song: song, progress: app.downloadProgress[song.id])
            }
        }
    }

    private var downloadedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("На устройстве".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(app.downloadedSongs) { song in
                        DownloadedSongRow(song: song)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Нет загруженных песен".localized)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct DownloadRow: View {
    let song: SubsonicSong
    let progress: Double?

    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(coverArt: song.coverArt, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                if let progress {
                    ProgressView(value: progress)
                        .controlSize(.mini)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            Spacer()
            Button {
                app.cancelDownload(song)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Отменить")
            .accessibilityLabel("Отменить загрузку")
        }
        .padding(.vertical, 2)
    }
}

private struct DownloadedSongRow: View {
    let song: SubsonicSong

    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(coverArt: song.coverArt, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let duration = song.duration {
                Text(Player.format(seconds: Double(duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await app.removeFromCache(song) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Удалить загрузку")
            .accessibilityLabel("Удалить загрузку")
        }
        .padding(.vertical, 2)
    }
}