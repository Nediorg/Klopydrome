import SwiftUI
import AppKit
import Quartz

struct QuickLookCover: NSViewRepresentable {
    let coverArt: String?
    var size: CGFloat = 220
    var cornerRadius: CGFloat?
    var shadow: Bool = true
    var title: String?

    func makeNSView(context: Context) -> NSQuickLookView {
        let view = NSQuickLookView()
        view.title = title
        view.size = size
        view.coverArt = coverArt
        view.preparePreviewItemIfNeeded()
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
        if nsView.coverArt != coverArt, let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            nsView.closePreview()
        }
        nsView.title = title
        nsView.size = size
        nsView.coverArt = coverArt
        nsView.preparePreviewItemIfNeeded()
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
        var title: String? {
            didSet {
                if title != oldValue {
                    let itemTitle = title ?? "Cover".localized
                    previewItem?.previewItemTitle = itemTitle
                }
            }
        }
        var size: CGFloat = 220
        var coverArt: String? {
            didSet {
                if coverArt != oldValue {
                    preparePreviewItemIfNeeded()
                }
            }
        }
        var hostingView: NSHostingView<CoverArtView>?
        private var previewItem: CoverPreviewItem?
        private var previewCoverArt: String?
        private var forceFired = false
        private var openTask: Task<Void, Never>?
        private var upgradeTask: Task<Void, Never>?

        func closePreview() {
            openTask?.cancel()
            openTask = nil
            upgradeTask?.cancel()
            upgradeTask = nil
            previewItem = nil
            previewCoverArt = nil
        }

        func preparePreviewItemIfNeeded() {
            guard let coverArt, !coverArt.isEmpty else {
                previewItem = nil
                previewCoverArt = nil
                return
            }
            let itemTitle = title ?? "Cover".localized
            if previewCoverArt == coverArt, let item = previewItem {
                item.previewItemTitle = itemTitle
                return
            }
            if let directURL = CoverArtStore.shared.cachedQuickLookFileURL(
                coverArt: coverArt,
                displayPixels: Int(size * 2)
            ) {
                previewItem = CoverPreviewItem(url: directURL, title: itemTitle)
                previewCoverArt = coverArt
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            forceFired = false
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func pressureChange(with event: NSEvent) {
            super.pressureChange(with: event)
            if event.stage == 2, !forceFired {
                forceFired = true
                openPreview()
            }
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard !forceFired else { return }
            let loc = convert(event.locationInWindow, from: nil)
            guard bounds.contains(loc) else { return }
            openPreview()
        }

        override func quickLook(with event: NSEvent) {
            openPreview()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 {
                openPreview()
                return
            }
            super.keyDown(with: event)
        }

        @MainActor
        private func openPreview() {
            guard let coverArt, !coverArt.isEmpty else { return }
            openTask?.cancel()

            if let panel = QLPreviewPanel.shared(), panel.isVisible {
                if previewCoverArt == coverArt {
                    panel.close()
                    return
                }
            }

            preparePreviewItemIfNeeded()

            if previewItem != nil {
                guard let panel = QLPreviewPanel.shared() else { return }
                panel.dataSource = self
                panel.delegate = self
                configurePanelGeometry(panel, coverArt: coverArt)
                panel.reloadData()
                if !panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                }
                upgradeToFullCoverInBackground(coverArt: coverArt)
                return
            }

            startOpenTask(coverArt: coverArt)
        }

        @MainActor
        private func startOpenTask(coverArt: String) {
            previewCoverArt = coverArt
            openTask = Task { @MainActor [weak self] in
                guard let self else { return }

                guard let initialURL = await CoverArtStore.shared.quickLookFileURL(
                    coverArt: coverArt,
                    displayPixels: Int(self.size * 2)
                ) else { return }
                guard !Task.isCancelled, self.coverArt == coverArt else { return }

                let itemTitle = self.title ?? "Cover".localized
                self.previewItem = CoverPreviewItem(url: initialURL, title: itemTitle)

                guard let panel = QLPreviewPanel.shared() else { return }
                panel.dataSource = self
                panel.delegate = self
                self.configurePanelGeometry(panel, coverArt: coverArt)
                panel.reloadData()
                if !panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                }
                self.upgradeToFullCoverInBackground(coverArt: coverArt)
            }
        }

        @MainActor
        private func upgradeToFullCoverInBackground(coverArt: String) {
            upgradeTask?.cancel()
            upgradeTask = Task { @MainActor [weak self] in
                guard let self else { return }

                guard let fullURL = await CoverArtStore.shared.fullCoverFileURL(coverArt: coverArt) else { return }
                guard !Task.isCancelled,
                      self.coverArt == coverArt,
                      self.previewCoverArt == coverArt else { return }
                guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }

                if self.previewItem?.previewItemURL != fullURL {
                    let itemTitle = self.title ?? "Cover".localized
                    self.previewItem = CoverPreviewItem(url: fullURL, title: itemTitle)
                    self.configurePanelGeometry(panel, coverArt: coverArt)
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

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewItem == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            previewItem
        }

        func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
            guard coverArt == previewCoverArt, let window = window else { return .zero }
            let frameInWindow = convert(bounds, to: nil)
            return window.convertToScreen(frameInWindow)
        }

        func previewPanel(
            _ panel: QLPreviewPanel!,
            transitionImageFor item: QLPreviewItem!,
            contentRect: UnsafeMutablePointer<NSRect>!
        ) -> Any! {
            nil
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
            guard let coverArt, !coverArt.isEmpty else { return false }
            return true
        }

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            preparePreviewItemIfNeeded()
            panel.dataSource = self
            panel.delegate = self
            if let coverArt {
                configurePanelGeometry(panel, coverArt: coverArt)
            }
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            if let current = panel.currentPreviewItem as? CoverPreviewItem,
               current === previewItem,
               panel.isVisible {
                return
            }
            panel.dataSource = nil
            panel.delegate = nil
            panel.contentAspectRatio = .zero
            closePreview()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

final class CoverPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    var previewItemTitle: String?

    init(url: URL, title: String?) {
        self.previewItemURL = url
        self.previewItemTitle = title
        super.init()
    }
}
