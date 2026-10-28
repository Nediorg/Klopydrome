import AppKit
import CoreImage
import Foundation
import NavidromeClient
import SwiftUI

final class MiniPlayerVariableBlurCache: @unchecked Sendable {
    static let shared = MiniPlayerVariableBlurCache()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 16
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func clear() {
        lock.withLock { cache.removeAllObjects() }
    }

    static func blurCoverage(for height: Double) -> Double {
        let clampedHeight = min(600.0, max(320.0, height))
        let slope = (320.0 - 250.0) / (600.0 - 320.0)
        return 250.0 + (clampedHeight - 320.0) * slope
    }

    static func startFraction(for height: Double) -> Double {
        guard height > 0 else { return 0.22 }
        let coverage = blurCoverage(for: height)
        return max(0.0, (height - coverage) / height)
    }

    func cached(coverArt: String, targetSize: CGSize) -> NSImage? {
        let key = cacheKey(coverArt: coverArt, targetSize: targetSize)
        return lock.withLock { cache.object(forKey: key) }
    }

    func prewarmBlur(coverArt: String, size: CGFloat) {
        let targetSize = CGSize(width: size, height: size)
        let key = cacheKey(coverArt: coverArt, targetSize: targetSize)
        if lock.withLock({ cache.object(forKey: key) != nil }) {
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let sourceBox = await CoverArtStore.shared.image(coverArt: coverArt, size: Int(size * 2))
            guard let sourceImage = sourceBox.image else { return }
            _ = self.renderBlur(coverArt: coverArt, source: sourceImage, targetSize: targetSize)
        }
    }

    func renderBlur(coverArt: String, source: NSImage, targetSize: CGSize) -> NSImage? {
        let key = cacheKey(coverArt: coverArt, targetSize: targetSize)
        if let existing = lock.withLock({ cache.object(forKey: key) }) {
            return existing
        }

        let sourceCI: CIImage
        if let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            sourceCI = CIImage(cgImage: cgImage)
        } else if let tiffData = source.tiffRepresentation,
                  let parsed = CIImage(data: tiffData) {
            sourceCI = parsed
        } else {
            return nil
        }

        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        guard width > 0, height > 0 else { return nil }

        guard let scaledCI = aspectFillCropped(sourceCI: sourceCI, width: width, height: height) else {
            return nil
        }

        guard let maskCI = createMaskImage(width: width, height: height)?.clampedToExtent() else { return nil }
        guard let filter = CIFilter(name: "CIMaskedVariableBlur") else { return nil }
        filter.setValue(scaledCI, forKey: kCIInputImageKey)
        filter.setValue(maskCI, forKey: "inputMask")

        let radius = max(18.0, Double(width) * (26.0 / 512.0))
        filter.setValue(radius, forKey: "inputRadius")

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let outCI = filter.outputImage,
              let blurredCG = context.createCGImage(outCI, from: rect) else {
            return nil
        }

        let result = NSImage(cgImage: blurredCG, size: targetSize)
        let cost = width * height * 4
        lock.withLock {
            cache.setObject(result, forKey: key, cost: cost)
        }
        return result
    }

    private func aspectFillCropped(sourceCI: CIImage, width: Int, height: Int) -> CIImage? {

        let sourceExtent = sourceCI.extent
        let sourceWidth = sourceExtent.width
        let sourceHeight = sourceExtent.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let targetAspect = CGFloat(width) / CGFloat(height)
        let sourceAspect = sourceWidth / sourceHeight

        let cropRect: CGRect
        if sourceAspect > targetAspect {
            let visibleWidth = sourceHeight * targetAspect
            let originX = sourceExtent.origin.x + (sourceWidth - visibleWidth) / 2.0
            cropRect = CGRect(x: originX, y: sourceExtent.origin.y, width: visibleWidth, height: sourceHeight)
        } else {
            let visibleHeight = sourceWidth / targetAspect
            let originY = sourceExtent.origin.y + (sourceHeight - visibleHeight) / 2.0
            cropRect = CGRect(x: sourceExtent.origin.x, y: originY, width: sourceWidth, height: visibleHeight)
        }

        let croppedCI = sourceCI.cropped(to: cropRect)
        let translatedCI = croppedCI.transformed(
            by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        )
        let scale = CGFloat(width) / cropRect.width
        return translatedCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).clampedToExtent()
    }

    private func createMaskImage(width: Int, height: Int) -> CIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let rawData = ctx.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else {
            return nil
        }

        let coverage = Self.blurCoverage(for: Double(height))
        let startRow = max(0.0, Double(height) - coverage)
        let endRow = Double(height)
        let rowSpan = max(1.0, endRow - startRow)

        for row in 0..<height {
            let rowDouble = Double(row)
            let progress: Double
            if rowDouble < startRow {
                progress = 0.0
            } else {
                progress = min(1.0, (rowDouble - startRow) / rowSpan)
            }
            let greenValue = UInt8(clamping: Int(progress * 255.0))
            for col in 0..<width {
                let offset = (row * width + col) * 4
                rawData[offset + 0] = greenValue
                rawData[offset + 1] = greenValue
                rawData[offset + 2] = greenValue
                rawData[offset + 3] = 255
            }
        }

        guard let maskCG = ctx.makeImage() else { return nil }
        return CIImage(cgImage: maskCG)
    }

    private func cacheKey(coverArt: String, targetSize: CGSize) -> NSString {
        "\(coverArt)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
    }
}

struct MiniPlayerBlurredArtworkView: View {
    @Environment(AppState.self) private var app

    let coverArt: String?
    let size: CGFloat

    @State private var blurredImage: NSImage?
    @State private var previousBlurredImage: NSImage?
    @State private var renderedCoverArt: String?
    @State private var previousCoverArt: String?

    init(coverArt: String?, size: CGFloat) {
        self.coverArt = coverArt
        self.size = size
        let targetSize = CGSize(width: size, height: size)
        let cached = coverArt.flatMap {
            MiniPlayerVariableBlurCache.shared.cached(coverArt: $0, targetSize: targetSize)
        }
        _blurredImage = State(initialValue: cached)
        _renderedCoverArt = State(initialValue: cached != nil ? coverArt : nil)
    }

    var body: some View {
        ZStack {
            if let previousBlurredImage, previousCoverArt != renderedCoverArt {
                Image(nsImage: previousBlurredImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .allowsHitTesting(false)
            }

            if let blurredImage {
                Image(nsImage: blurredImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .id(renderedCoverArt)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            darkeningGradient
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.28), value: renderedCoverArt)
        .task(id: "\(coverArt ?? "")-\(Int(size))") {
            await loadBlurredArtwork()
        }
    }

    private func loadBlurredArtwork() async {
        guard let coverArt, !coverArt.isEmpty else {
            withAnimation(.easeInOut(duration: 0.18)) {
                previousBlurredImage = nil
                previousCoverArt = nil
                blurredImage = nil
                renderedCoverArt = nil
            }
            return
        }

        if blurredImage != nil, renderedCoverArt == coverArt {
            prewarmNeighbors()
            return
        }

        let targetSize = CGSize(width: size, height: size)
        let result: NSImage?
        if let cached = MiniPlayerVariableBlurCache.shared.cached(coverArt: coverArt, targetSize: targetSize) {
            result = cached
        } else {
            let sourceBox = await CoverArtStore.shared.image(coverArt: coverArt, size: Int(size * 2))
            guard let sourceImage = sourceBox.image else { return }

            result = await Task.detached(priority: .userInitiated) {
                MiniPlayerVariableBlurCache.shared.renderBlur(
                    coverArt: coverArt,
                    source: sourceImage,
                    targetSize: targetSize
                )
            }.value
        }

        guard !Task.isCancelled, let newBlur = result else { return }

        if let existing = blurredImage, let rendered = renderedCoverArt, rendered != coverArt {
            previousBlurredImage = existing
            previousCoverArt = rendered
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            blurredImage = newBlur
            renderedCoverArt = coverArt
        }

        prewarmNeighbors()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if renderedCoverArt == coverArt {
                previousBlurredImage = nil
                previousCoverArt = nil
            }
        }
    }

    private func prewarmNeighbors() {
        let player = app.player
        let nextIndex = player.currentIndex + 1
        if player.queue.indices.contains(nextIndex), let nextArt = player.queue[nextIndex].coverArt {
            MiniPlayerVariableBlurCache.shared.prewarmBlur(coverArt: nextArt, size: size)
        }
        let prevIndex = player.currentIndex - 1
        if player.queue.indices.contains(prevIndex), let prevArt = player.queue[prevIndex].coverArt {
            MiniPlayerVariableBlurCache.shared.prewarmBlur(coverArt: prevArt, size: size)
        }
    }

    private var darkeningGradient: some View {
        let start = MiniPlayerVariableBlurCache.startFraction(for: Double(size))
        let span = 1.0 - start
        return LinearGradient(
            stops: [
                .init(color: .clear, location: start),
                .init(color: .black.opacity(0.16), location: start + span * 0.35),
                .init(color: .black.opacity(0.32), location: start + span * 0.70),
                .init(color: .black.opacity(0.46), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
