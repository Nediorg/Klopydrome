import SwiftUI
import NavidromeClient

struct ContentPillContainer<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.12), value: hovering)
    }
}

struct PlaylistPillCard: View {
    let playlist: PlaylistSummary
    let onTap: () -> Void

    private var fallbackPreset: PlaylistCoverPreset {
        PlaylistCoverPreset.preset(for: playlist.id)
    }

    var body: some View {
        ContentPillContainer(action: onTap) {
            HStack(spacing: 10) {
                if let coverArt = playlist.coverArt, !coverArt.isEmpty {
                    CoverArtView(coverArt: coverArt, size: 40, cornerRadius: 4)
                } else {
                    CoverPresetView(preset: fallbackPreset, size: 40, title: playlist.displayName)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.displayName)
                        .font(AMFont.rowTitle)
                        .lineLimit(1)
                    Text("Playlist".localized)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            PlaylistContextMenuItems(playlist: playlist)
        }
    }
}

struct ArtistPillCard: View {
    let artist: Artist
    let onTap: () -> Void

    var body: some View {
        ContentPillContainer(action: onTap) {
            HStack(spacing: 10) {
                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(AMFont.rowTitle)
                        .lineLimit(1)
                    Text("Artist".localized)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            ArtistContextMenuItems(artist: artist)
        }
    }
}

struct AlbumPillCard: View {
    let album: SubsonicAlbum
    let onTap: () -> Void

    var body: some View {
        ContentPillContainer(action: onTap) {
            HStack(spacing: 10) {
                CoverArtView(coverArt: album.coverArt, size: 40, cornerRadius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.displayName)
                        .font(AMFont.rowTitle)
                        .lineLimit(1)
                    Text(album.artist ?? "Album".localized)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            AlbumContextMenuItems(album: album)
        }
    }
}

struct SongPillCard: View {
    let song: SubsonicSong
    let isCurrent: Bool
    let onPlay: () -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        ContentPillContainer(action: onPlay) {
            HStack(spacing: 10) {
                ZStack {
                    CoverArtView(coverArt: song.coverArt, size: 40, cornerRadius: 4)
                    if isCurrent {
                        Color.black.opacity(0.35)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(AMFont.rowTitle)
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? AMColor.accent : .primary)
                    Text(subtitleText)
                        .font(AMFont.rowSubtitle)
                        .foregroundStyle(AMColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isCurrent ? AMColor.accent : Color.secondary)
            }
        }
        .contextMenu {
            SongActionItems(app: app, song: song, onPlay: onPlay)
        }
    }

    private var subtitleText: String {
        let type = "Song".localized
        if let artist = song.artist, !artist.isEmpty {
            return "\(type) · \(artist)"
        }
        return type
    }
}
