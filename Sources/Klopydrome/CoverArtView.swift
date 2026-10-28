import SwiftUI
import AppKit

struct CoverArtView: View {
    let coverArt: String?
    let size: CGFloat
    var cornerRadius: CGFloat?
    var shadow = false
    var placeholderBackground: Color?

    /// Corner radius scales with size: small thumbnails ~4pt, grid covers ~6pt,
    /// large hero covers ~8pt matching Apple Music macOS Sequoia.
    private var radius: CGFloat {
        if let cornerRadius { return cornerRadius }
        if size < 64 { return 4 }
        if size < 180 { return 6 }
        return 8
    }
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

    init(coverArt: String?, size: CGFloat, cornerRadius: CGFloat? = nil, shadow: Bool = false,
         placeholderBackground: Color? = nil) {
        self.coverArt = coverArt
        self.size = size
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.placeholderBackground = placeholderBackground
        let cached = CoverArtStore.shared.cachedImage(coverArt: coverArt, size: Int(size * 2))
        _image = State(initialValue: cached)
        _renderedCoverArt = State(initialValue: cached != nil ? coverArt : nil)
    }

    private var displayImage: NSImage? {
        if let cached = CoverArtStore.shared.cachedImage(coverArt: coverArt, size: Int(size * 2)) {
            return cached
        }
        // Retain previous image while loading a new valid cover art:
        if coverArt?.isEmpty == false, let image {
            return image
        }
        return nil
    }

    private var currentCoverID: String {
        if CoverArtStore.shared.cachedImage(coverArt: coverArt, size: Int(size * 2)) != nil,
           let art = coverArt, !art.isEmpty {
            return art
        }
        if let renderedCoverArt, !renderedCoverArt.isEmpty {
            return renderedCoverArt
        }
        return coverArt ?? "cover-placeholder"
    }

    var body: some View {
        ZStack {
            if let displayImage {
                Image(nsImage: displayImage)
                    .resizable()
                    .scaledToFill()
                    .id(currentCoverID)
                    .transition(.opacity)
            } else if placeholderBackground != .clear {
                ZStack {
                    Rectangle().fill(placeholderBackground ?? Color.primary.opacity(0.08))
                        .shimmering(coverArt?.isEmpty == false && !loadFailed && size >= 60)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            } else {
                Color.clear
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if placeholderBackground != .clear || displayImage != nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .coverShadow(enabled: shadow, radius: shadowRadius, yOffset: shadowY)
        .accessibilityLabel(coverArt ?? String(localized: "Обложка"))
        .accessibilityAddTraits(.isImage)
        .animation(.easeInOut(duration: 0.22), value: renderedCoverArt)
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
            if image != nil, renderedCoverArt == art {
                return
            }
            // Fast cache hit avoiding placeholder flash and shimmer animation:
            if let cached = CoverArtStore.shared.cachedImage(coverArt: art, size: Int(size * 2)) {
                withAnimation(.easeInOut(duration: 0.20)) {
                    image = cached
                    renderedCoverArt = art
                }
                loadFailed = false
                return
            }

            loadFailed = false

            // Grace period: if we already have an image visible, give the new
            // cover 350ms to resolve (from disk cache or fast connection) before
            // dropping to the placeholder. If it resolves in time, we transition
            // directly between the covers without flashing a placeholder.
            let hadPreviousImage = (image != nil)

            enum LoadingResult: Sendable {
                case image(CoverArtStore.ImageBox)
                case graceExpired
            }

            await withTaskGroup(of: LoadingResult.self) { group in
                group.addTask {
                    let outcome = await CoverArtStore.shared.image(coverArt: art, size: Int(size * 2))
                    return .image(CoverArtStore.ImageBox(image: outcome.image))
                }

                if hadPreviousImage {
                    group.addTask {
                        try? await Task.sleep(for: .milliseconds(350))
                        return .graceExpired
                    }
                }

                for await result in group {
                    guard !Task.isCancelled else { break }
                    switch result {
                    case .graceExpired:
                        withAnimation(.easeInOut(duration: 0.20)) {
                            image = nil
                            renderedCoverArt = nil
                        }
                    case .image(let box):
                        group.cancelAll()
                        if let newImage = box.image {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                image = newImage
                                renderedCoverArt = art
                            }
                            loadFailed = false
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                image = nil
                                renderedCoverArt = nil
                            }
                            loadFailed = true
                        }
                        return
                    }
                }
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

private extension View {
    @ViewBuilder
    func coverShadow(enabled: Bool, radius: CGFloat, yOffset: CGFloat) -> some View {
        if enabled {
            self.shadow(color: .black.opacity(0.30), radius: radius, y: yOffset)
        } else {
            self
        }
    }
}
