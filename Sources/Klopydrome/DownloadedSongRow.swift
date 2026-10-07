import SwiftUI
import NavidromeClient

/// A single song row in the downloaded offline library section of the downloads popover.
struct DownloadedSongRow: View {
    let song: SubsonicSong
    let isSelected: Bool
    var resolveSelection: (() -> [SubsonicSong])?
    let onSelect: () -> Void

    @Environment(AppState.self) private var app
    @State private var isHovered = false

    private var isCurrentSong: Bool {
        app.player.currentSong?.id == song.id
    }

    private var contextMenuSelection: [SubsonicSong] {
        guard isSelected, let resolve = resolveSelection else { return [song] }
        return resolve()
    }

    var body: some View {
        HStack(spacing: 8) {
            artworkView

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(song.displayTitle)
                        .font(.system(size: 12, weight: isCurrentSong ? .semibold : .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(song.artist ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                handlePlay()
            }
            .simultaneousGesture(TapGesture().onEnded {
                onSelect()
            })

            trailingActionView
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            rowBackground
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            SongActionItems(
                app: app,
                song: song,
                selection: contextMenuSelection,
                onPlay: { handlePlay() }
            )
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        ZStack {
            CoverArtView(coverArt: song.coverArt, size: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            if isHovered || isCurrentSong {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 34, height: 34)

                Button {
                    handlePlay()
                } label: {
                    Image(systemName: isCurrentSong && app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(isCurrentSong && app.player.isPlaying ? "Пауза".localized : "Слушать".localized)
            }
        }
        .frame(width: 34, height: 34)
        .onTapGesture { onSelect() }
    }

    @ViewBuilder
    private var trailingActionView: some View {
        if isHovered {
            Button {
                let selected = resolveSelection?() ?? []
                let toDelete = (isSelected || selected.contains(where: { $0.id == song.id })) && !selected.isEmpty
                    ? selected
                    : [song]
                Task {
                    for item in toDelete {
                        await app.removeFromCache(item)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Удалить загрузку".localized)
            .accessibilityLabel("Удалить загрузку".localized)
        } else {
            HStack(spacing: 4) {
                if isCurrentSong {
                    Image(systemName: app.player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let duration = song.duration {
                    Text(Player.format(seconds: Double(duration)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.12))
        } else if isHovered {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }

    private func handlePlay() {
        if isCurrentSong {
            app.player.togglePlayPause()
        } else {
            let index = app.downloadedSongs.firstIndex(where: { $0.id == song.id }) ?? 0
            app.player.play(app.downloadedSongs, startAt: index)
        }
    }
}
