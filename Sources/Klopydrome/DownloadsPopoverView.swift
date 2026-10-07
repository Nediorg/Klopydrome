import SwiftUI
import NavidromeClient

/// The anchored toolbar popover listing offline downloads:
/// high-level active batch tasks (album, playlist, genre) with live progress,
/// and the finished song list with full playback, selection, and context-menu controls.
struct DownloadsPopoverView: View {
    @Environment(AppState.self) private var app
    @State private var selection = SongRowSelection()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if hasActiveDownloads {
                activeSection
                Divider()
            }

            if app.downloadedSongs.isEmpty {
                emptyState
            } else {
                downloadedSection
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var hasActiveDownloads: Bool {
        !app.activeDownloadTasks.isEmpty || !app.downloadingSongs.isEmpty
    }

    private var header: some View {
        HStack {
            Text("Загрузки".localized)
                .font(.headline)
            Spacer()
            if app.nav.selectedPlaylist != nil {
                Button("Загрузить плейлист".localized) { app.cacheCurrentPlaylist() }
                    .buttonStyle(.borderless)
            } else {
                Button("Загрузить альбом".localized) { app.cacheCurrentAlbum() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 4)
    }

    private var activeCount: Int {
        if !app.activeDownloadTasks.isEmpty {
            return app.activeDownloadTasks.count
        }
        return app.downloadingSongs.count
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("В процессе".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if activeCount > 2 {
                ScrollView {
                    activeItemsContent
                }
                .frame(maxHeight: 240)
            } else {
                activeItemsContent
            }
        }
    }

    @ViewBuilder
    private var activeItemsContent: some View {
        VStack(spacing: 2) {
            if !app.activeDownloadTasks.isEmpty {
                ForEach(app.activeDownloadTasks) { task in
                    DownloadTaskRow(task: task)
                }
            } else {
                ForEach(app.downloadingSongs) { song in
                    DownloadRow(song: song, progress: app.downloadProgress[song.id] ?? 0.0)
                }
            }
        }
    }

    private var downloadedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("На устройстве".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(app.downloadedSongs) { song in
                        DownloadedSongRow(
                            song: song,
                            isSelected: selection.isSelected(song.id),
                            resolveSelection: { selection.selectedSongs(from: app.downloadedSongs) },
                            onSelect: { selection.toggle(song.id, allSongs: app.downloadedSongs) }
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
            .onDeleteCommand {
                let toDelete = selection.selectedSongs(from: app.downloadedSongs)
                if !toDelete.isEmpty {
                    Task {
                        for song in toDelete {
                            await app.removeFromCache(song)
                        }
                    }
                }
            }
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

private struct DownloadTaskRow: View {
    let task: DownloadTask
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            mainRowContent

            ZStack(alignment: .top) {
                if isExpanded {
                    expandedTracksList
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
            .mask(Rectangle())
        }
    }

    private var mainRowContent: some View {
        HStack(spacing: 8) {
            Button {
                handleNavigate()
            } label: {
                HStack(spacing: 8) {
                    if let coverArt = task.coverArt {
                        CoverArtView(coverArt: coverArt, size: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        taskIcon
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Text(task.currentSongSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            ProgressView(value: task.progress(downloadProgress: app.downloadProgress))
                                .controlSize(.mini)

                            if task.totalCount > 1 {
                                Text("\(task.completedCount)/\(task.totalCount)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            trailingControls
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 2) {
            if task.totalCount > 1 {
                Button {
                    withAnimation(Motion.spring(Motion.expand)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Свернуть треки".localized : "Показать треки".localized)
            }

            Button {
                app.cancelDownloadTask(task)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Отменить".localized)
            .accessibilityLabel("Отменить загрузку".localized)
        }
    }

    @ViewBuilder
    private var expandedTracksList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 1) {
                ForEach(task.songs) { song in
                    TaskTrackRow(
                        taskID: task.id,
                        song: song,
                        isCompleted: task.completedSongIDs.contains(song.id),
                        isCurrent: task.currentSongID == song.id
                    )
                }
            }
            .padding(.trailing, 2)
        }
        .frame(height: min(CGFloat(max(task.songs.count, 1)) * 26, 180))
        .padding(.leading, 42)
        .padding(.trailing, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var taskIcon: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
    }

    private var iconName: String {
        switch task.kind {
        case .playlist: return "music.note.list"
        case .album: return "square.stack"
        case .genre: return "guitars"
        case .track, .batch: return "music.note"
        }
    }

    private func handleNavigate() {
        switch task.kind {
        case .playlist(let playlist):
            dismiss()
            app.openPlaylist(playlist)
        case .album(let album):
            dismiss()
            app.openAlbumInLibrary(album)
        case .genre(let name):
            dismiss()
            app.openGenre(name)
        case .track(let song):
            dismiss()
            app.openSongDetails(song)
        case .batch:
            break
        }
    }
}

private struct TaskTrackRow: View {
    let taskID: UUID
    let song: SubsonicSong
    let isCompleted: Bool
    let isCurrent: Bool

    @Environment(AppState.self) private var app
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(song.displayTitle)
                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            trailingStatus
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if isCompleted {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AMColor.accent)
                .frame(width: 16, height: 16)
        } else if isCurrent {
            HStack(spacing: 4) {
                ProgressView(value: app.downloadProgress[song.id] ?? 0.0)
                    .controlSize(.mini)
                    .frame(width: 30)

                Button {
                    app.cancelDownloadSongInTask(taskID: taskID, song: song)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Отменить трек".localized)
            }
        } else if isHovered {
            Button {
                app.cancelDownloadSongInTask(taskID: taskID, song: song)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Отменить трек".localized)
        } else {
            Image(systemName: "clock")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 16)
        }
    }
}

private struct DownloadRow: View {
    let song: SubsonicSong
    let progress: Double?

    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            CoverArtView(coverArt: song.coverArt, size: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(song.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                ProgressView(value: progress ?? 0.0)
                    .controlSize(.mini)
                    .frame(width: 32)

                Button {
                    app.cancelDownload(song)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Отменить".localized)
                .accessibilityLabel("Отменить загрузку".localized)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}