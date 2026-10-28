import SwiftUI
import AppKit
import Combine

@main
struct KlopydromeApp: App {
    @NSApplicationDelegateAdaptor(KlopydromeApplicationDelegate.self) private var appDelegate
    @State private var app = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
        TitlebarPassThrough.installGlobal()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .frame(minWidth: LayoutMetrics.windowMinWidth, minHeight: 600)
                .task { await app.reconnectIfPossible() }
        }
        .defaultSize(width: 1180, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppCommandMenus(app: app)
        }

        Settings {
            AppSettingsView()
                .environment(app)
        }
    }

}

@MainActor
private final class KlopydromeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if MiniPlayerPanelController.shared.isPanelActive {
            MiniPlayerPanelController.shared.activate()
            return false
        }
        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var app

    @State private var spaceBarMonitor: Any?

    var body: some View {
        ZStack {
            MainView()
                .onAppear {
                    CoverArtStore.shared.configure(
                        client: app.client,
                        cache: app.cache,
                        coverResolution: app.serverConfig.coverResolution ?? .high,
                        adaptiveCellularDataEnabled: app.serverConfig.effectiveAdaptiveCellularDataEnabled
                    )
                }
                .onChange(of: app.isConnected) { _, _ in
                    CoverArtStore.shared.configure(
                        client: app.client,
                        cache: app.cache,
                        coverResolution: app.serverConfig.coverResolution ?? .high,
                        adaptiveCellularDataEnabled: app.serverConfig.effectiveAdaptiveCellularDataEnabled
                    )
                }
                .onChange(of: app.isOfflineSession) { _, _ in
                    CoverArtStore.shared.configure(
                        client: app.client,
                        cache: app.cache,
                        coverResolution: app.serverConfig.coverResolution ?? .high,
                        adaptiveCellularDataEnabled: app.serverConfig.effectiveAdaptiveCellularDataEnabled
                    )
                }
            if app.shouldShowLoginView {
                AMColor.background.ignoresSafeArea()
                Image(systemName: "music.note.list")
                    .font(.system(size: 180, weight: .ultraLight))
                    .foregroundStyle(Color.primary.opacity(0.05))
                    .accessibilityHidden(true)
                Color.black.opacity(0.45).ignoresSafeArea()
                LoginView()
                    .frame(width: 420)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(radius: 20)
            }
        }
        .background(WindowMinSizeConfigurator(
            minSize: NSSize(width: LayoutMetrics.windowMinWidth, height: 600)
        ))
        .background(AMColor.background)
        .preferredColorScheme(app.appearance)
        .onReceive(NotificationCenter.default.publisher(for: .mainWindowJoined)) { note in
            configureWindowToolbar(target: note.object as? NSWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { note in
            if let window = note.object as? NSWindow {
                configureWindow(window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await app.handleForegroundActivation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            app.savePlaybackExitPreferences()
        }
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            configureWindowToolbar()
            installSpaceBarMonitor()
        }
        .onDisappear {
            if let monitor = spaceBarMonitor {
                NSEvent.removeMonitor(monitor)
            }
            spaceBarMonitor = nil
        }
    }

    private func configureWindowToolbar(target: NSWindow? = nil) {
        let window = target ?? NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        guard let window else { return }
        configureWindow(window)
    }

    private func isMainPlayerWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        if window.isMainPlayerWindow { return true }
        if let content = window.contentView, containsMainWindowMarker(content) {
            window.isMainPlayerWindow = true
            return true
        }
        return false
    }

    private func containsMainWindowMarker(_ view: NSView) -> Bool {
        if view is WindowMinSizeView { return true }
        for sub in view.subviews where containsMainWindowMarker(sub) { return true }
        return false
    }

    private func configureWindow(_ window: NSWindow) {
        guard isMainPlayerWindow(window) else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.tabbingMode = .disallowed
        if let toolbar = window.toolbar {
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
        }
        window.titlebarSeparatorStyle = .none
        TitlebarPassThrough.configureWindow(window)
        DispatchQueue.main.async { [weak window] in
            func clearMenuRecursively(in view: NSView) {
                if String(describing: type(of: view)).contains("Toolbar") {
                    view.menu = nil
                }
                for sub in view.subviews { clearMenuRecursively(in: sub) }
            }
            guard let window else { return }
            if let root = window.contentView?.superview {
                clearMenuRecursively(in: root)
            }
            if let content = window.contentView {
                clearMenuRecursively(in: content)
            }
        }
        let floor = NSSize(width: LayoutMetrics.windowMinWidth, height: 600)
        window.contentMinSize = floor
        window.minSize = floor
        if window.frame.width < floor.width || window.frame.height < floor.height {
            var frame = window.frame
            frame.size.width = max(frame.size.width, floor.width)
            frame.size.height = max(frame.size.height, floor.height)
            window.setFrame(frame, display: true)
        }
    }

    private func installSpaceBarMonitor() {
        spaceBarMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 49, modifiers.isEmpty else { return event }
            guard let firstResponder = NSApp.keyWindow?.firstResponder else { return event }
            if firstResponder is NSTextView || firstResponder is NSControl { return event }
            Task { @MainActor in
                app.player.togglePlayPause()
            }
            return nil
        }
    }
}

extension Notification.Name {
    static let mainWindowJoined = Notification.Name("MainWindowJoined")
}

struct WindowMinSizeConfigurator: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        WindowMinSizeView(minSize: minSize)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowMinSizeView else { return }
        view.minSize = minSize
    }
}

private final class WindowMinSizeView: NSView {
    var minSize: NSSize {
        didSet { apply() }
    }

    init(minSize: NSSize) {
        self.minSize = minSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.isMainPlayerWindow = true
        }
        apply()
        if let window {
            NotificationCenter.default.post(name: .mainWindowJoined, object: window)
        }
    }

    private func apply() {
        guard let window else { return }
        window.contentMinSize = minSize
        window.minSize = minSize
        if window.frame.width < minSize.width || window.frame.height < minSize.height {
            var frame = window.frame
            frame.size.width = max(frame.size.width, minSize.width)
            frame.size.height = max(frame.size.height, minSize.height)
            window.setFrame(frame, display: true)
        }
    }
}

private var isPlayerWindowKey: UInt8 = 0

extension NSWindow {
    fileprivate var isMainPlayerWindow: Bool {
        get { (objc_getAssociatedObject(self, &isPlayerWindowKey) as? Bool) ?? false }
        set {
            objc_setAssociatedObject(
                self,
                &isPlayerWindowKey,
                newValue ? true : nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}