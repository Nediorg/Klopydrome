import AppKit
import SwiftUI

/// Owns one native mini-player panel. Artwork and lyrics/queue are sibling
/// hosting views so the lower section physically slides out of the same window.
@MainActor
final class MiniPlayerPanelController: NSObject, NSWindowDelegate {
    static let shared = MiniPlayerPanelController()

    private var panel: NSPanel?
    private var contentHost: NSView?
    private var artworkHost: MiniPlayerHostingView<AnyView>?
    private var detailClipHost: NSView?
    private var detailHost: NSHostingView<AnyView>?
    private var detailCollapsedHeightConstraint: NSLayoutConstraint?
    private var detailBottomConstraint: NSLayoutConstraint?
    private var configuredPanel: AppState.PlayerPanelTab?
    private weak var app: AppState?
    private weak var mainWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible == true }

    func show(app: AppState) {
        self.app = app
        let sourceWindow = NSApp.mainWindow === panel ? mainWindow : NSApp.mainWindow
        let shouldPositionPanel = panel == nil
        let panel = panel ?? makePanel(app: app)
        if shouldPositionPanel {
            position(panel, relativeTo: sourceWindow)
        }
        mainWindow = sourceWindow
        mainWindow?.orderOut(nil)
        activate()
        NotificationCenter.default.post(name: .miniPlayerDidOpen, object: nil)
    }

    func activate() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Returns focus to the main window before navigation consumes a request
    /// originating from the mini-player's otherwise isolated view hierarchy.
    func closeForLibraryNavigation() {
        panel?.close()
    }

    private func makePanel(app: AppState) -> NSPanel {
        let compactSize = NSSize(
            width: MiniPlayerLayout.compactSide,
            height: MiniPlayerLayout.compactSide
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = .zero
        panel.contentMinSize = .zero

        let contentHost = NSView(frame: NSRect(origin: .zero, size: compactSize))
        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentHost

        let rootView = AnyView(
            MiniPlayerView { [weak self] controlsVisible, activePanel in
                self?.updateChrome(controlsVisible: controlsVisible, activePanel: activePanel)
            }
            .environment(app)
            .ignoresSafeArea()
        )
        let artworkHost = MiniPlayerHostingView(rootView: rootView)
        artworkHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(artworkHost)
        NSLayoutConstraint.activate([
            artworkHost.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            artworkHost.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            artworkHost.topAnchor.constraint(equalTo: contentHost.topAnchor),
            artworkHost.heightAnchor.constraint(equalTo: artworkHost.widthAnchor)
        ])

        self.panel = panel
        self.contentHost = contentHost
        self.artworkHost = artworkHost
        updateChrome(controlsVisible: false, activePanel: nil)
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo sourceWindow: NSWindow?) {
        guard let sourceWindow else {
            panel.center()
            return
        }
        let visibleFrame = sourceWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let origin = NSPoint(
            x: sourceWindow.frame.midX - size.width / 2,
            y: sourceWindow.frame.midY - size.height / 2
        )
        let clampedOrigin = NSPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        panel.setFrameOrigin(clampedOrigin)
    }

    private func updateChrome(controlsVisible: Bool, activePanel: AppState.PlayerPanelTab?) {
        guard let panel else { return }
        setTrafficLights(in: panel, visible: controlsVisible)
        guard configuredPanel != activePanel else { return }
        configuredPanel = activePanel

        if let activePanel {
            presentDetail(activePanel, in: panel)
        } else {
            dismissDetail(in: panel)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let requestedContentSize = sender.contentRect(
            forFrameRect: NSRect(origin: .zero, size: frameSize)
        ).size
        let currentContentSize = sender.contentView?.bounds.size ?? requestedContentSize
        let contentSize: NSSize
        if configuredPanel != nil {
            contentSize = MiniPlayerResizeGeometry.contentSize(
                requested: requestedContentSize,
                current: currentContentSize
            )
        } else {
            contentSize = MiniPlayerResizeGeometry.collapsedSize(
                requested: requestedContentSize,
                current: currentContentSize
            )
        }
        MiniPlayerResizeGeometry.lastDebugLine =
            "req \(Int(requestedContentSize.width))×\(Int(requestedContentSize.height)) "
            + "cur \(Int(currentContentSize.width))×\(Int(currentContentSize.height)) → "
            + "\(Int(contentSize.width))×\(Int(contentSize.height))"
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        contentHost = nil
        artworkHost = nil
        detailClipHost = nil
        detailHost = nil
        detailCollapsedHeightConstraint = nil
        detailBottomConstraint = nil
        configuredPanel = nil
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow = nil
        NotificationCenter.default.post(name: .miniPlayerDidClose, object: nil)
    }

    private func presentDetail(_ kind: AppState.PlayerPanelTab, in panel: NSPanel) {
        let currentContentSize = panel.contentView?.bounds.size
            ?? panel.contentRect(forFrameRect: panel.frame).size
        let side = max(MiniPlayerLayout.minimumCompactSide, currentContentSize.width)
        installDetailHost(for: kind)
        detailCollapsedHeightConstraint?.isActive = false
        detailBottomConstraint?.isActive = true
        detailClipHost?.isHidden = false
        let targetSize = NSSize(width: side, height: side + MiniPlayerLayout.panelHeight)
        let targetFrame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        let anchored = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        contentHost?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MiniPlayerLayout.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(anchored, display: true)
            contentHost?.animator().layoutSubtreeIfNeeded()
        }
    }

    private func dismissDetail(in panel: NSPanel) {
        let currentContentSize = panel.contentView?.bounds.size
            ?? panel.contentRect(forFrameRect: panel.frame).size
        let side = max(MiniPlayerLayout.minimumCompactSide, currentContentSize.width)
        let targetSize = NSSize(width: side, height: side)
        let targetFrame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        let anchored = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        contentHost?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MiniPlayerLayout.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(anchored, display: true)
            contentHost?.animator().layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.configuredPanel == nil else { return }
                self?.detailBottomConstraint?.isActive = false
                self?.detailCollapsedHeightConstraint?.isActive = true
                self?.detailClipHost?.isHidden = true
                self?.contentHost?.layoutSubtreeIfNeeded()
            }
        }
    }

    private func installDetailHost(for panel: AppState.PlayerPanelTab) {
        guard let app, let contentHost, let artworkHost else { return }
        let rootView = AnyView(
            MiniPlayerPanelView(panel: panel)
                .environment(app)
        )

        if let detailHost {
            detailHost.rootView = rootView
            return
        }

        let detailClipHost = NSView()
        detailClipHost.wantsLayer = true
        detailClipHost.clipsToBounds = true
        detailClipHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(detailClipHost, positioned: .below, relativeTo: artworkHost)

        let detailHost = NSHostingView(rootView: rootView)
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        detailClipHost.addSubview(detailHost)

        let detailCollapsedHeightConstraint = detailClipHost.heightAnchor.constraint(equalToConstant: 0)
        let detailBottomConstraint = detailClipHost.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
        detailBottomConstraint.isActive = false
        NSLayoutConstraint.activate([
            detailClipHost.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            detailClipHost.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            detailClipHost.topAnchor.constraint(equalTo: artworkHost.bottomAnchor),
            detailCollapsedHeightConstraint,
            detailHost.leadingAnchor.constraint(equalTo: detailClipHost.leadingAnchor),
            detailHost.trailingAnchor.constraint(equalTo: detailClipHost.trailingAnchor),
            detailHost.topAnchor.constraint(equalTo: detailClipHost.topAnchor),
            detailHost.bottomAnchor.constraint(equalTo: detailClipHost.bottomAnchor)
        ])
        self.detailClipHost = detailClipHost
        self.detailHost = detailHost
        self.detailCollapsedHeightConstraint = detailCollapsedHeightConstraint
        self.detailBottomConstraint = detailBottomConstraint
    }

    private func setTrafficLights(in panel: NSPanel, visible: Bool) {
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { panel.standardWindowButton($0)?.isHidden = !visible }
    }

    /// Whether the cursor is anywhere inside the panel, chrome included.
    /// Backs the hide decision in `MiniPlayerView.updateHover`.
    var isCursorInsidePanel: Bool {
        guard let panel, let content = panel.contentView else { return false }
        let point = content.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        return content.bounds.contains(point)
    }
}

extension Notification.Name {
    static let miniPlayerDidOpen = Notification.Name("miniPlayerDidOpen")
    static let miniPlayerDidClose = Notification.Name("miniPlayerDidClose")
}

private final class MiniPlayerHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

enum MiniPlayerResizeGeometry {
    static var lastDebugLine = ""

    /// Sizing for the OPEN detail panel only. A horizontal-only drag keeps the
    /// WINDOW height fixed: the artwork side follows the requested width and
    /// takes the difference out of the panel (never below its minimum). Every
    /// other drag routes the height delta into the panel.
    static func contentSize(requested: NSSize, current: NSSize) -> NSSize {
        let side = max(MiniPlayerLayout.minimumCompactSide, requested.width)
        let widthChanged = abs(requested.width - current.width) > 0.5
        let heightChanged = abs(requested.height - current.height) > 0.5
        if widthChanged && !heightChanged {
            let height = max(side + MiniPlayerLayout.minimumDetailHeight, current.height)
            return NSSize(width: side, height: height)
        }
        let detailHeight = max(MiniPlayerLayout.minimumDetailHeight, requested.height - side)
        return NSSize(width: side, height: side + detailHeight)
    }

    /// Collapsed square sizing without the native aspect ratio (whose clearing
    /// is unreliable mid-gesture). The side tracks whichever axis the drag is
    /// actually moving so an edge gesture never fights the perpendicular snap;
    /// corner drags fall back to the dominant axis.
    static func collapsedSize(requested: NSSize, current: NSSize) -> NSSize {
        let widthChanged = abs(requested.width - current.width) > 0.5
        let heightChanged = abs(requested.height - current.height) > 0.5
        let side: CGFloat
        if widthChanged && !heightChanged {
            side = requested.width
        } else if heightChanged && !widthChanged {
            side = requested.height
        } else {
            side = max(requested.width, requested.height)
        }
        let clamped = max(MiniPlayerLayout.minimumCompactSide, side)
        return NSSize(width: clamped, height: clamped)
    }
}

enum MiniPlayerLayout {
    static let compactSide: CGFloat = 420
    static let minimumCompactSide: CGFloat = 320
    static let panelHeight: CGFloat = 300
    static let minimumDetailHeight: CGFloat = 180
    static let panelAnimationDuration: TimeInterval = 0.22
    static let topMenuEdgeInset: CGFloat = 7
    static let topMenuTrailingInset: CGFloat = 3.5
}
