import SwiftUI
import AppKit
import Quartz

/// Wraps `CoverArtView` in an AppKit view that fires on both regular click
/// (mouseDown) and Force Touch deep press (pressure stage 2 at the moment of
/// pressing) and opens `QLPreviewPanel` with a zoom animation from the cover's
/// on-screen frame — exactly like Finder.
struct QuickLookCover: NSViewRepresentable {
    let coverArt: String?
    var size: CGFloat = 220
    var cornerRadius: CGFloat?
    var shadow: Bool = true
    var title: String?

    func makeNSView(context: Context) -> NSQuickLookView {
        let view = NSQuickLookView()
        view.coverArt = coverArt
        view.size = size
        view.title = title
        let hosting = NSHostingView(
            rootView: CoverArtView(coverArt: coverArt, size: size, cornerRadius: cornerRadius, shadow: shadow)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.hostingView = hosting
        return view
    }

    func updateNSView(_ nsView: NSQuickLookView, context: Context) {
        // If Quick Look is open for the old cover and user navigated to a
        // different album/playlist, dismiss without zooming back to the
        // stale frame — return .zero in sourceFrame handles the unzoom,
        // but we also close immediately to avoid showing wrong content.
        if nsView.coverArt != coverArt, let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            nsView.closePreview()
        }
        nsView.coverArt = coverArt
        nsView.size = size
        nsView.title = title
        if let hosting = nsView.hostingView {
            hosting.rootView = CoverArtView(
                coverArt: coverArt,
                size: size,
                cornerRadius: cornerRadius,
                shadow: shadow
            )
        }
    }

    static func dismantleNSView(_ nsView: NSQuickLookView, coordinator: ()) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible, panel.dataSource === nsView {
            panel.orderOut(nil)
        }
        nsView.closePreview()
    }

    final class NSQuickLookView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var coverArt: String?
        var size: CGFloat = 220
        var title: String?
        var hostingView: NSHostingView<CoverArtView>?
        private var previewItem: CoverPreviewItem?
        /// CoverArt that the currently open panel is previewing — used to
        /// suppress unzoom animation when user navigated away.
        private var previewCoverArt: String?
        private var forceFired = false
        private var openTask: Task<Void, Never>?

        func closePreview() {
            openTask?.cancel()
            openTask = nil
            previewItem = nil
            previewCoverArt = nil
        }

        override func mouseDown(with event: NSEvent) {
            forceFired = false
            super.mouseDown(with: event)
        }

        override func pressureChange(with event: NSEvent) {
            super.pressureChange(with: event)
            if event.stage == 2, !forceFired {
                forceFired = true
                Task { @MainActor in self.openPreview() }
            }
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard !forceFired else { return }
            let loc = convert(event.locationInWindow, from: nil)
            guard bounds.contains(loc) else { return }
            Task { @MainActor in self.openPreview() }
        }

        override func quickLook(with event: NSEvent) {
            Task { @MainActor in self.openPreview() }
        }

        @MainActor
        private func openPreview() {
            guard let coverArt, !coverArt.isEmpty else { return }
            openTask?.cancel()

            if let panel = QLPreviewPanel.shared(), panel.isVisible {
                if previewCoverArt == coverArt {
                    panel.orderOut(nil)
                    closePreview()
                    return
                }
            }

            startOpenTask(coverArt: coverArt)
        }

        @MainActor
        private func startOpenTask(coverArt: String) {
            previewCoverArt = coverArt
            openTask = Task { @MainActor [weak self] in
                guard let self else { return }

                // 1. Resolve an immediate file URL for Quick Look from disk cache or memory cache (< 5ms).
                guard let initialURL = await CoverArtStore.shared.quickLookFileURL(
                    coverArt: coverArt,
                    displayPixels: Int(self.size * 2)
                ) else { return }
                guard !Task.isCancelled, self.coverArt == coverArt else { return }

                let itemTitle = self.title ?? String(localized: "Обложка")
                self.previewItem = CoverPreviewItem(url: initialURL, title: itemTitle)

                guard let panel = QLPreviewPanel.shared() else { return }
                panel.dataSource = self
                panel.delegate = self
                self.configurePanelGeometry(panel, coverArt: coverArt)
                panel.reloadData()
                if !panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                }

                // 2. If the initial URL is a thumbnail/preview, fetch the full-res original cover in background.
                let isFull = await CoverArtStore.shared.isFullCoverCached(coverArt: coverArt)
                if !isFull {
                    guard let fullURL = await CoverArtStore.shared.fullCoverFileURL(coverArt: coverArt) else { return }
                    guard !Task.isCancelled, self.coverArt == coverArt, self.previewCoverArt == coverArt else { return }
                    self.previewItem = CoverPreviewItem(url: fullURL, title: itemTitle)
                    panel.reloadData()
                }
            }
        }

        private func configurePanelGeometry(_ panel: QLPreviewPanel, coverArt: String) {
            guard let screen = window?.screen ?? NSScreen.main else { return }
            let imageSize = CoverArtStore.shared.anyCachedImage(
                coverArt: coverArt,
                preferredDisplayPixels: Int(size * 2)
            )?.size

            let screenFrame = screen.visibleFrame
            let aspect: CGFloat
            if let imageSize, imageSize.width > 0 && imageSize.height > 0 {
                aspect = imageSize.width / imageSize.height
                panel.contentAspectRatio = NSSize(width: imageSize.width, height: imageSize.height)
            } else {
                aspect = 1.0
                panel.contentAspectRatio = NSSize(width: 1, height: 1)
            }

            let maxDim = min(screenFrame.height * 0.70, screenFrame.width * 0.70, 750)
            let targetWidth = aspect >= 1.0 ? maxDim : round(maxDim * aspect)
            let targetHeight = aspect >= 1.0 ? round(maxDim / aspect) : maxDim

            let originX = round(screenFrame.midX - targetWidth / 2)
            let originY = round(screenFrame.midY - targetHeight / 2)
            let contentRect = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)
            panel.setFrame(panel.frameRect(forContentRect: contentRect), display: false)
        }

        // MARK: QLPreviewPanelDataSource
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItem == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            previewItem
        }

        // MARK: QLPreviewPanelDelegate — zoom from cover frame on open, clean fade on close
        func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
            // Only provide a source frame when opening the panel.
            // When closing (panel is already visible), returning .zero triggers a clean
            // fade-out, avoiding stale zoom-back animations if the user navigated away
            // (e.g. to Home/Playlists or different views) or scrolled the content.
            guard !panel.isVisible else { return .zero }

            guard coverArt == previewCoverArt, let window = window else { return .zero }
            let frameInWindow = convert(bounds, to: nil)
            return window.convertToScreen(frameInWindow)
        }

        func previewPanel(
            _ panel: QLPreviewPanel!,
            transitionImageFor item: QLPreviewItem!,
            contentRect: UnsafeMutablePointer<NSRect>!
        ) -> Any! {
            guard let coverArt else { return nil }
            return CoverArtStore.shared.anyCachedImage(
                coverArt: coverArt,
                preferredDisplayPixels: Int(size * 2)
            )
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = self
            panel.delegate = self
        }
        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = nil
            panel.delegate = nil
            panel.contentAspectRatio = .zero
            closePreview()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Simple `QLPreviewItem` wrapper that provides a clean user-facing title
/// in the Quick Look title bar instead of temporary raw cache filenames.
final class CoverPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String?) {
        self.previewItemURL = url
        self.previewItemTitle = title
        super.init()
    }
}
