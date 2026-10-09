import SwiftUI
import NavidromeClient

/// A compact Apple Music-style pill card container used across Home and Search.
/// Features an 8pt continuous corner radius, subtle hover feedback, and full hit-target coverage.
struct ContentPillContainer<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
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

/// Compact pill card representing a playlist.
struct PlaylistPillCard: View {
    let playlist: PlaylistSummary
    let onTap: () -> Void

    private var fallbackPreset: PlaylistCoverPreset {
        let presets = PlaylistCoverPreset.all
        let index = abs(playlist.id.hashValue) % presets.count
        return presets[index]
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
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Плейлист".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

/// Compact pill card representing an artist.
struct ArtistPillCard: View {
    let artist: Artist
    let onTap: () -> Void

    var body: some View {
        ContentPillContainer(action: onTap) {
            HStack(spacing: 10) {
                CircularArtistArt(name: artist.name, imageURL: artist.artistImageUrl, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Исполнитель".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

/// Compact pill card representing an album.
struct AlbumPillCard: View {
    let album: SubsonicAlbum
    let onTap: () -> Void

    var body: some View {
        ContentPillContainer(action: onTap) {
            HStack(spacing: 10) {
                CoverArtView(coverArt: album.coverArt, size: 40, cornerRadius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(album.artist ?? "Альбом".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
