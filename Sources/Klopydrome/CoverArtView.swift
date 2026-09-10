import SwiftUI
import AppKit

struct CoverArtView: View {
    let coverArt: String?
    let size: CGFloat
    var cornerRadius: CGFloat?
    var shadow = false
    var placeholderBackground: Color?

    /// Corner radius scales with size: small thumbnails ~4pt, large hero covers
    /// ~12pt (HIG_COMPLIANCE §1.3).
    private var radius: CGFloat { cornerRadius ?? (size < 64 ? 4 : 12) }
    /// Drop shadow scales with the cover so hero artwork reads with depth
    /// (HIG §1.3: ~y8/blur24/30%) without swamping small thumbnails.
    private var shadowRadius: CGFloat { shadow ? max(8, size * 0.08) : 0 }
    private var shadowY: CGFloat { shadow ? max(4, size * 0.03) : 0 }

    @State private var image: NSImage?
    /// The identifier of the rendered artwork; changing it gives SwiftUI an
    /// insertion/removal pair for a short opacity transition without dropping
    /// the previous cover while the next one is loading.
    @State private var renderedCoverArt: String?
    /// Set when the store reports the artwork doesn't exist (dead/empty cover,
    /// network failure): the placeholder stops shimmering and stays a static
    /// tile instead of animating indefinitely. Cleared when a new cover id
    /// starts loading, so a later-successful tile still gets its sweep.
    @State private var loadFailed = false
    /// Bumped by `foregroundRefreshRequested` (failed covers are invalidated
    /// store-wide on activation): part of the task id so visible tiles
    /// re-request even though their cover id never changed.
    @State private var retryNonce = 0

    var body: some View {
        Group {
            if let image, let renderedCoverArt, renderedCoverArt == coverArt {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .id(renderedCoverArt)
                    .transition(.opacity)
            } else {
                ZStack {
                    Rectangle().fill(placeholderBackground ?? Color.primary.opacity(0.08))
                        .shimmering(coverArt?.isEmpty == false && !loadFailed && size >= 60)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(shadow ? 0.30 : 0), radius: shadowRadius, y: shadowY)
        .accessibilityLabel(coverArt ?? String(localized: "Обложка"))
        .accessibilityAddTraits(.isImage)
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            // Resume shimmer immediately; the re-fired task below fills the image.
            loadFailed = false
            retryNonce += 1
        }
        .task(id: CoverArtRequest(art: coverArt, nonce: retryNonce)) {
            // Debounce rapid changes: `coverArt` can flip several times while
            // a playlist jumps between songs. `.task(id:)` cancels the prior
            // task, but cancelling is not synchronous, so guard the awaited
            // result so an earlier fetch can't overwrite fresh artwork.
            // (The id above only restarts the task; values come from capture.)
            guard let art = coverArt, !art.isEmpty else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    image = nil
                    renderedCoverArt = nil
                }
                loadFailed = false
                return
            }
            // If the art changed, drop the old image immediately so the
            // placeholder (shimmer) shows while the new one loads — don't
            // keep showing the previous cover until the fetch finishes.
            if renderedCoverArt != art {
                image = nil
                renderedCoverArt = nil
            }
            loadFailed = false
            let loaded = await CoverArtStore.shared.image(coverArt: art, size: Int(size * 2))
            guard !Task.isCancelled else { return }
            if let image = loaded.image {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.image = image
                    renderedCoverArt = art
                }
            } else {
                loadFailed = true
            }
        }
    }
}

/// Task identity for artwork loads: the cover id plus a retry nonce so a
/// foreground refresh re-fires visible tiles whose id never changed.
/// Shared with artist tiles (`ArtistsView`).
struct CoverArtRequest: Equatable {
    var art: String?
    var nonce: Int
}

/// A 2-column technical-metadata grid for a song (bitrate, format, duration,
/// path, ids, …). Shared by the song detail page and the mini-player popover.

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
