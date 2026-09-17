import AppKit
import NavidromeClient
import SwiftUI

/// Circular 32x32 info button matching RoundFavoriteButton and RoundEllipsisMenu.
struct RoundInfoButton: View {
    var size: CGFloat = 32
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hovering ? AMColor.surfaceTertiaryHover : AMColor.surfaceLight)
                    .frame(width: size, height: size)

                Image(systemName: "info")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .help("Сведения об исполнителе".localized)
        .accessibilityLabel("Сведения об исполнителе".localized)
    }
}

/// Full-bleed hero banner for the artist page matching Apple Music macOS Sequoia.
///
/// Spans edge-to-edge with a charcoal gray background, a centered circular avatar,
/// a bottom-left cluster with a red Play button + artist title/details, and
/// right-aligned action buttons (favorite, ellipsis menu, and details).
struct ArtistHeroBanner: View {
    let artist: Artist
    let detail: ArtistDetail
    let roleLabel: String?
    let albums: [SubsonicAlbum]
    let allSongs: [SubsonicSong]
    let artistInfo: ArtistInfoPayload?
    let gatheringSongs: Bool
    let onPlay: () -> Void
    var onShowInfo: (() -> Void)?

    @Environment(AppState.self) private var app
    @State private var playHovered = false

    private var artistName: String {
        detail.name ?? artist.name
    }

    /// Dynamic charcoal gray background matching Apple Music dark appearance.
    private var bannerBackground: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 0.15, green: 0.15, blue: 0.165, alpha: 1.0)
            } else {
                return NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1.0)
            }
        }))
    }

    /// Unique genres collected from albums and tracks.
    private var genresSummary: String? {
        let set = Set(albums.compactMap(\.genre) + allSongs.compactMap(\.genre))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let sorted = Array(set).sorted()
        if sorted.isEmpty { return nil }
        return sorted.prefix(3).joined(separator: ", ")
    }

    /// Concatenated summary subtitle (role, genre, albums/songs count, total time).
    private var detailsText: String? {
        var parts: [String] = []
        if let roleLabel, !roleLabel.isEmpty {
            parts.append(roleLabel)
        }
        if let genresSummary {
            parts.append(genresSummary)
        }
        let albumCount = detail.albumCount ?? albums.count
        if albumCount > 0 {
            parts.append("\(albumCount) \(Pluralized.album(albumCount))")
        }
        if !allSongs.isEmpty {
            parts.append("\(allSongs.count) \(Pluralized.song(allSongs.count))")
            let totalSeconds = allSongs.reduce(0) { $0 + ($1.duration ?? 0) }
            if totalSeconds > 0 {
                parts.append(Player.format(seconds: Double(totalSeconds)))
            }
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bannerBackground

            // Center: Circular Avatar
            VStack {
                Spacer()
                avatarView
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // Bottom bar: Controls & Details
            bottomBar
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
    }

    // MARK: Avatar

    private var avatarView: some View {
        let imageURL = detail.artistImageUrl ?? artist.artistImageUrl
        return Group {
            if let imageURL, !imageURL.isEmpty {
                CircularArtistArt(name: artistName, imageURL: imageURL, size: 130)
            } else if let coverArt = detail.coverArt, !coverArt.isEmpty {
                CoverArtView(coverArt: coverArt, size: 130)
                    .clipShape(Circle())
            } else {
                CircularArtistArt(name: artistName, imageURL: nil, size: 130)
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 16) {
            // Left: Red Play Button + Artist Title & Details
            HStack(spacing: 14) {
                playButton

                VStack(alignment: .leading, spacing: 3) {
                    Text(artistName)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let detailsText {
                        Text(detailsText)
                            .font(.subheadline)
                            .foregroundStyle(AMColor.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 16)

            // Right: Action buttons
            HStack(spacing: 8) {
                RoundFavoriteButton(isStarred: app.isStarred(artist)) {
                    app.toggleStar(artist)
                }
                RoundEllipsisMenu {
                    ArtistContextMenuItems(artist: artist)
                }
                RoundInfoButton {
                    onShowInfo?()
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            ZStack {
                Circle()
                    .fill(AMColor.accent)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .brightness(playHovered ? 0.08 : 0)

                if gatheringSongs {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { playHovered = $0 }
        .help("Слушать исполнителя".localized)
        .accessibilityLabel("Слушать исполнителя".localized)
    }
}
