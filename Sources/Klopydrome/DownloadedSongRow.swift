import SwiftUI
import NavidromeClient

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
                        .font(AMFont.miniTitle)
                        .foregroundStyle(isCurrentSong ? AMColor.accent : Color.primary)
                        .lineLimit(1)

                    Text(song.artist ?? "")
                        .font(AMFont.miniSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
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

            if isCurrentSong && !isHovered {
                Color.black.opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            } else if isHovered {
                Color.black.opacity(0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Button {
                    handlePlay()
                } label: {
                    Image(systemName: isCurrentSong && app.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(isCurrentSong && app.player.isPlaying ? "Pause".localized : "Play".localized)
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
            .help("Delete Download".localized)
            .accessibilityLabel("Delete Download".localized)
        } else {
            HStack(spacing: 4) {
                if let duration = song.duration {
                    Text(Player.format(seconds: Double(duration)))
                        .font(AMFont.miniSubtitle.monospacedDigit())
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
            app.play(app.downloadedSongs, at: index)
        }
    }
}
