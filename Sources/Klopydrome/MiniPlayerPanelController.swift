import AppKit
import SwiftUI

@MainActor
final class MiniPlayerPanelController: NSObject {
    static let shared = MiniPlayerPanelController()

    private var panel: NSPanel?
    private var contentHost: NSView?
    private var artworkHost: MiniPlayerHostingView<AnyView>?
    private var detailClipHost: NSView?
    private var detailHost: NSHostingView<AnyView>?
    private var detailCollapsedHeightConstraint: NSLayoutConstraint?
    private var detailBottomConstraint: NSLayoutConstraint?
    private var detailHostHeightConstraint: NSLayoutConstraint?
    private var configuredPanel: AppState.PlayerPanelTab?
    var userCompactSide: CGFloat = MiniPlayerLayout.compactSide
    var userDetailHeight: CGFloat = MiniPlayerLayout.panelHeight
    private var isAnimatingDetailTransition = false
    private var transitionGeneration = 0
    private weak var app: AppState?
    private weak var mainWindow: NSWindow?

    var isPanelActive: Bool { panel != nil }
    var isVisible: Bool { panel?.isVisible == true }

    func show(app: AppState) {
        self.app = app
        if let coverArt = app.player.displaySong?.coverArt {
            MiniPlayerVariableBlurCache.shared.prewarmBlur(coverArt: coverArt, size: userCompactSide)
        }
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
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeForLibraryNavigation() {
        panel?.close()
    }

    private func makePanel(app: AppState) -> NSPanel {
        let compactSize = NSSize(
            width: userCompactSide,
            height: userCompactSide
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanelProperties(panel)

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

    private func configurePanelProperties(_ panel: NSPanel) {
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let minSize = NSSize(
            width: MiniPlayerLayout.minimumCompactSide,
            height: MiniPlayerLayout.minimumCompactSide
        )
        let maxSize = NSSize(
            width: MiniPlayerLayout.maximumCompactSide,
            height: MiniPlayerLayout.maximumCompactSide + MiniPlayerLayout.panelHeight + 200
        )
        panel.minSize = minSize
        panel.maxSize = maxSize
        panel.contentMinSize = minSize
        panel.contentMaxSize = maxSize
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

    private func presentDetail(_ kind: AppState.PlayerPanelTab, in panel: NSPanel) {
        let currentFrame = panel.frame
        let currentWidth = panel.contentRect(forFrameRect: currentFrame).width
        let side = min(
            max(MiniPlayerLayout.minimumCompactSide, currentWidth > 0 ? currentWidth : userCompactSide),
            MiniPlayerLayout.maximumCompactSide
        )
        userCompactSide = side
        installDetailHost(for: kind)
        detailHostHeightConstraint?.constant = userDetailHeight
        detailCollapsedHeightConstraint?.isActive = false
        detailBottomConstraint?.isActive = true
        detailClipHost?.isHidden = false
        let targetSize = NSSize(width: side, height: side + userDetailHeight)
        let targetFrame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))

        var originX = currentFrame.minX
        var originY = currentFrame.maxY - targetFrame.height

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            originX = min(max(originX, visible.minX), visible.maxX - currentFrame.width)
            originY = min(max(originY, visible.minY), visible.maxY - targetFrame.height)
        }

        let anchored = NSRect(
            x: originX,
            y: originY,
            width: currentFrame.width,
            height: targetFrame.height
        )

        transitionGeneration += 1
        let currentGeneration = transitionGeneration
        isAnimatingDetailTransition = true

        contentHost?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MiniPlayerLayout.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(anchored, display: true)
            contentHost?.animator().layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.transitionGeneration == currentGeneration else { return }
                self?.isAnimatingDetailTransition = false
            }
        }
    }

    private func dismissDetail(in panel: NSPanel) {
        let currentFrame = panel.frame
        let currentWidth = panel.contentRect(forFrameRect: currentFrame).width
        let side = min(
            max(MiniPlayerLayout.minimumCompactSide, currentWidth > 0 ? currentWidth : userCompactSide),
            MiniPlayerLayout.maximumCompactSide
        )
        userCompactSide = side
        let targetSize = NSSize(width: side, height: side)
        let targetFrame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))

        var originX = currentFrame.minX
        var originY = currentFrame.maxY - targetFrame.height

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            originX = min(max(originX, visible.minX), visible.maxX - currentFrame.width)
            originY = min(max(originY, visible.minY), visible.maxY - targetFrame.height)
        }

        let anchored = NSRect(
            x: originX,
            y: originY,
            width: currentFrame.width,
            height: targetFrame.height
        )

        transitionGeneration += 1
        let currentGeneration = transitionGeneration
        isAnimatingDetailTransition = true

        contentHost?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MiniPlayerLayout.panelAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(anchored, display: true)
            contentHost?.animator().layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.transitionGeneration == currentGeneration else { return }
                self?.isAnimatingDetailTransition = false
                guard self?.configuredPanel == nil else { return }
                self?.detailBottomConstraint?.isActive = false
                self?.detailCollapsedHeightConstraint?.isActive = true
                self?.detailClipHost?.isHidden = true
                self?.detailHost?.rootView = AnyView(EmptyView())
                self?.contentHost?.layoutSubtreeIfNeeded()
            }
        }
    }

    private func installDetailHost(for panel: AppState.PlayerPanelTab) {
        guard let app, let contentHost, let artworkHost else { return }
        let rootView = AnyView(
            MiniPlayerPanelView(panel: panel)
                .environment(app)
                .ignoresSafeArea()
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

        let detailHostHeightConstraint = detailHost.heightAnchor.constraint(equalToConstant: userDetailHeight)
        detailHostHeightConstraint.priority = NSLayoutConstraint.Priority(999)

        NSLayoutConstraint.activate([
            detailClipHost.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            detailClipHost.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            detailClipHost.topAnchor.constraint(equalTo: artworkHost.bottomAnchor),
            detailCollapsedHeightConstraint,
            detailHost.leadingAnchor.constraint(equalTo: detailClipHost.leadingAnchor),
            detailHost.trailingAnchor.constraint(equalTo: detailClipHost.trailingAnchor),
            detailHost.topAnchor.constraint(equalTo: detailClipHost.topAnchor),
            detailHostHeightConstraint,
            detailHost.bottomAnchor.constraint(greaterThanOrEqualTo: detailClipHost.bottomAnchor)
        ])
        self.detailClipHost = detailClipHost
        self.detailHost = detailHost
        self.detailCollapsedHeightConstraint = detailCollapsedHeightConstraint
        self.detailBottomConstraint = detailBottomConstraint
        self.detailHostHeightConstraint = detailHostHeightConstraint
    }

    private func setTrafficLights(in panel: NSPanel, visible: Bool) {
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { panel.standardWindowButton($0)?.isHidden = !visible }
    }

    var isLiveResizing: Bool {
        panel?.inLiveResize == true
    }

    var isCursorInsidePanel: Bool {
        guard let panel, let content = panel.contentView else { return false }
        if panel.inLiveResize { return true }
        let point = content.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        return content.bounds.insetBy(dx: -8, dy: -8).contains(point)
    }
}

extension MiniPlayerPanelController: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender.inLiveResize, !isAnimatingDetailTransition else {
            return frameSize
        }
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
        userCompactSide = contentSize.width
        if configuredPanel != nil {
            userDetailHeight = max(MiniPlayerLayout.minimumDetailHeight, contentSize.height - contentSize.width)
            detailHostHeightConstraint?.constant = userDetailHeight
        }
        MiniPlayerResizeGeometry.lastDebugLine =
            "req \(Int(requestedContentSize.width))×\(Int(requestedContentSize.height)) "
            + "cur \(Int(currentContentSize.width))×\(Int(currentContentSize.height)) → "
            + "\(Int(contentSize.width))×\(Int(contentSize.height))"
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = (notification.object as? NSPanel) ?? self.panel, !isAnimatingDetailTransition else { return }
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let width = contentSize.width
        if width >= MiniPlayerLayout.minimumCompactSide && width <= MiniPlayerLayout.maximumCompactSide {
            userCompactSide = width
        }
        if configuredPanel != nil {
            userDetailHeight = max(MiniPlayerLayout.minimumDetailHeight, contentSize.height - contentSize.width)
            detailHostHeightConstraint?.constant = userDetailHeight
        }
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else { return defaultFrame }
        let visibleFrame = screen.visibleFrame
        let targetSide = MiniPlayerLayout.maximumCompactSide
        let currentContentSize = window.contentView?.bounds.size
            ?? window.contentRect(forFrameRect: window.frame).size

        let targetContentHeight: CGFloat
        if configuredPanel != nil {
            let currentDetailHeight = max(
                MiniPlayerLayout.minimumDetailHeight,
                currentContentSize.height - currentContentSize.width
            )
            targetContentHeight = targetSide + currentDetailHeight
        } else {
            targetContentHeight = targetSide
        }

        let targetContentSize = NSSize(width: targetSide, height: targetContentHeight)
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size

        var originX = window.frame.minX
        var originY = window.frame.maxY - targetFrameSize.height

        if originX + targetFrameSize.width > visibleFrame.maxX {
            originX = visibleFrame.maxX - targetFrameSize.width
        }
        if originX < visibleFrame.minX {
            originX = visibleFrame.minX
        }
        if originY < visibleFrame.minY {
            originY = visibleFrame.minY
        }
        if originY + targetFrameSize.height > visibleFrame.maxY {
            originY = visibleFrame.maxY - targetFrameSize.height
        }

        return NSRect(origin: NSPoint(x: originX, y: originY), size: targetFrameSize)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        contentHost = nil
        artworkHost = nil
        detailClipHost = nil
        detailHost = nil
        detailCollapsedHeightConstraint = nil
        detailBottomConstraint = nil
        detailHostHeightConstraint = nil
        configuredPanel = nil
        isAnimatingDetailTransition = false
        transitionGeneration += 1
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow = nil
        NotificationCenter.default.post(name: .miniPlayerDidClose, object: nil)
    }
}

extension Notification.Name {
    static let miniPlayerDidOpen = Notification.Name("miniPlayerDidOpen")
    static let miniPlayerDidClose = Notification.Name("miniPlayerDidClose")
}

private final class MiniPlayerHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}
