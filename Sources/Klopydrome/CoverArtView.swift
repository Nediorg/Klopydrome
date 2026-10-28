import SwiftUI
import AppKit

struct CoverArtView: View {
    let coverArt: String?
    let size: CGFloat
    var cornerRadius: CGFloat?
    var shadow = false
    var placeholderBackground: Color?

    private var radius: CGFloat {
        if let cornerRadius { return cornerRadius }
        if size < 64 { return 4 }
        if size < 180 { return 6 }
        return 8
    }
    private var shadowRadius: CGFloat { shadow ? max(8, size * 0.08) : 0 }
    private var shadowY: CGFloat { shadow ? max(4, size * 0.03) : 0 }

    @State private var image: NSImage?
    @State private var previousImage: NSImage?
    @State private var renderedCoverArt: String?
    @State private var previousCoverArt: String?
    @State private var loadFailed = false
    @State private var retryNonce = 0

    init(coverArt: String?, size: CGFloat, cornerRadius: CGFloat? = nil, shadow: Bool = false,
         placeholderBackground: Color? = nil) {
        self.coverArt = coverArt
        self.size = size
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.placeholderBackground = placeholderBackground
        if placeholderBackground == .clear {
            _image = State(initialValue: nil)
            _renderedCoverArt = State(initialValue: nil)
        } else {
            let cached = CoverArtStore.shared.cachedImage(coverArt: coverArt, size: Int(size * 2))
            _image = State(initialValue: cached)
            _renderedCoverArt = State(initialValue: cached != nil ? coverArt : nil)
        }
    }

    var body: some View {
        ZStack {
            if let previousImage, previousCoverArt != renderedCoverArt {
                Image(nsImage: previousImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .allowsHitTesting(false)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .id(renderedCoverArt)
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
            if placeholderBackground != .clear || image != nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .coverShadow(enabled: shadow, radius: shadowRadius, yOffset: shadowY)
        .accessibilityLabel(coverArt ?? "Cover".localized)
        .accessibilityAddTraits(.isImage)
        .animation(.easeInOut(duration: 0.28), value: renderedCoverArt)
        .onReceive(NotificationCenter.default.publisher(for: .foregroundRefreshRequested)) { _ in
            loadFailed = false
            retryNonce += 1
        }
        .task(id: CoverArtRequest(art: coverArt, nonce: retryNonce)) {
            guard let art = coverArt, !art.isEmpty else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    previousImage = nil
                    previousCoverArt = nil
                    image = nil
                    renderedCoverArt = nil
                }
                loadFailed = false
                return
            }
            if image != nil, renderedCoverArt == art {
                return
            }
            if let cached = CoverArtStore.shared.cachedImage(coverArt: art, size: Int(size * 2)) {
                if image != nil, renderedCoverArt != art {
                    previousImage = image
                    previousCoverArt = renderedCoverArt
                }
                withAnimation(.easeInOut(duration: 0.28)) {
                    image = cached
                    renderedCoverArt = art
                }
                loadFailed = false
                schedulePreviousImageCleanup(for: art)
                return
            }

            loadFailed = false

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
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                previousImage = nil
                                previousCoverArt = nil
                                image = nil
                                renderedCoverArt = nil
                            }
                        }
                    case .image(let box):
                        group.cancelAll()
                        await MainActor.run {
                            if let newImage = box.image {
                                if image != nil, renderedCoverArt != art {
                                    previousImage = image
                                    previousCoverArt = renderedCoverArt
                                }
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    image = newImage
                                    renderedCoverArt = art
                                }
                                loadFailed = false
                                schedulePreviousImageCleanup(for: art)
                            } else {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    previousImage = nil
                                    previousCoverArt = nil
                                    image = nil
                                    renderedCoverArt = nil
                                }
                                loadFailed = true
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    private func schedulePreviousImageCleanup(for art: String) {
        guard previousImage != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if renderedCoverArt == art {
                previousImage = nil
                previousCoverArt = nil
            }
        }
    }
}

struct CoverArtRequest: Equatable {
    var art: String?
    var nonce: Int
}

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
