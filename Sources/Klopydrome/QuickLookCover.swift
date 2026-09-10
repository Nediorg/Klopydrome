import SwiftUI
import AppKit
import Quartz

/// Wraps `CoverArtView` in an AppKit view that fires on both regular click
/// (mouseDown) and Force Touch deep press (pressure stage 2 at the moment of
/// pressing) and opens `QLPreviewPanel` with a zoom animation from the cover's
/// on-screen frame — exactly like Finder.
struct QuickLookCover: NSViewRepresentable {
    let coverArt: String?

    func makeNSView(context: Context) -> NSQuickLookView {
        let view = NSQuickLookView()
        view.coverArt = coverArt
        let hosting = NSHostingView(rootView: CoverArtView(coverArt: coverArt, size: 220, shadow: true))
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
        if let hosting = nsView.hostingView {
            hosting.rootView = CoverArtView(coverArt: coverArt, size: 220, shadow: true)
        }
    }

    final class NSQuickLookView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var coverArt: String?
        var hostingView: NSHostingView<CoverArtView>?
        private var previewURL: URL?
        /// CoverArt that the currently open panel is previewing — used to
        /// suppress unzoom animation when user navigated away.
        private var previewCoverArt: String?
        private var forceFired = false
        private var isOpening = false
        private var openTask: Task<Void, Never>?

        func closePreview() {
            openTask?.cancel()
            openTask = nil
            previewURL = nil
            previewCoverArt = nil
            isOpening = false
        }

        override func mouseDown(with event: NSEvent) {
            forceFired = false
            super.mouseDown(with: event)
            if !forceFired { Task { @MainActor in self.openPreview() } }
        }

        override func pressureChange(with event: NSEvent) {
            if event.stage == 2, !forceFired {
                forceFired = true
                Task { @MainActor in self.openPreview() }
            }
            super.pressureChange(with: event)
        }

        @MainActor
        private func openPreview() {
            guard let coverArt, !coverArt.isEmpty else { return }
            openTask?.cancel()
            if let panel = QLPreviewPanel.shared(), panel.isVisible,
               handleVisiblePanel(panel, coverArt: coverArt) { return }
            startOpenTask(coverArt: coverArt)
        }

        @MainActor
        private func handleVisiblePanel(_ panel: QLPreviewPanel, coverArt: String) -> Bool {
            if previewCoverArt == coverArt {
                if isOpening {
                    openTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        if panel.isVisible { panel.orderOut(nil) }
                    }
                } else {
                    panel.orderOut(nil)
                }
                return true
            }
            if isOpening {
                openTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    self.openPreview()
                }
                return true
            }
            return false
        }

        @MainActor
        private func startOpenTask(coverArt: String) {
            isOpening = true
            // Open panel immediately with no preview — user sees window and
            // knows action started, image appears when download finishes.
            previewCoverArt = coverArt
            previewURL = nil
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = self
            panel?.delegate = self
            panel?.updateController()
            panel?.makeKeyAndOrderFront(nil)
            openTask = Task { @MainActor in
                guard let fullURL = await CoverArtStore.shared.fullCoverFileURL(coverArt: coverArt) else {
                    self.isOpening = false
                    return
                }
                guard !Task.isCancelled, self.coverArt == coverArt else {
                    self.isOpening = false
                    return
                }
                self.previewURL = fullURL
                QLPreviewPanel.shared()?.updateController()
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.isOpening = false
            }
        }

        // MARK: QLPreviewPanelDataSource
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            previewURL as QLPreviewItem?
        }

        // MARK: QLPreviewPanelDelegate — zoom from cover frame
        func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
            // If user navigated to a different album while panel is open, don't
            // zoom back to the stale cover frame — fade instead.
            guard coverArt == previewCoverArt, let window = window else { return .zero }
            let frameInWindow = convert(bounds, to: nil)
            return window.convertToScreen(frameInWindow)
        }

        func previewPanel(
            _ panel: QLPreviewPanel!,
            transitionImageFor item: QLPreviewItem!,
            contentRect: UnsafeMutablePointer<NSRect>!
        ) -> Any! {
            // Let Quick Look handle sizing naturally — no forced aspect.
            return nil
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = self
            panel.delegate = self
        }
        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = nil
            panel.delegate = nil
            closePreview()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
