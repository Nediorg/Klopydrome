import SwiftUI
import NavidromeClient

enum TrackDownloadStyle {
    case roundedCircle
    case tableCell
}

struct TrackDownloadButton: View {
    let song: SubsonicSong
    let app: AppState
    var isHovered: Bool = false
    var style: TrackDownloadStyle = .roundedCircle
    var size: CGFloat = 16

    private var isDownloading: Bool {
        app.downloadingSongIDs.contains(song.id)
    }

    private var isCachedLocally: Bool {
        app.isCached(song)
    }

    var body: some View {
        if isDownloading {
            Button {
                app.cancelSongDownload(song)
            } label: {
                ProgressView()
                    .controlSize(.mini)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cancel Download".localized)
            .accessibilityLabel("Cancel Download".localized)
            .frame(width: size, height: size)
        } else if isCachedLocally {
            Button {
                Task { await app.removeFromCache(song) }
            } label: {
                if style == .tableCell {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: size * 0.85))
                        .foregroundStyle(AMColor.accent)
                        .symbolEffect(.bounce, value: isCachedLocally)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("Delete Download".localized)
            .accessibilityLabel("Delete Download".localized)
            .frame(width: size, height: size)
        } else if isHovered || style == .tableCell {
            if !app.isOfflineSession {
                Button {
                    app.cacheSong(song)
                } label: {
                    if style == .tableCell {
                        Image(systemName: "arrow.down.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: size * 0.85))
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .help("Download".localized)
                .accessibilityLabel("Download".localized)
                .frame(width: size, height: size)
            } else {
                Color.clear.frame(width: size, height: size)
            }
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct TrackFavoriteButton: View {
    let song: SubsonicSong
    let app: AppState
    var isHovered: Bool = false
    var size: CGFloat = 16

    private var isStarred: Bool {
        app.isStarred(song)
    }

    var body: some View {
        if isStarred || isHovered {
            Button {
                app.toggleStar(song)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(AMColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isStarred ? "Remove from Favorites".localized : "Add to Favorites".localized)
            .frame(width: size, height: size)
        } else {
            Color.clear
                .frame(width: size, height: size)
        }
    }
}
