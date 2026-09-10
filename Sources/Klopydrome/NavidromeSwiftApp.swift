import SwiftUI
import AppKit
import Combine

@main
struct KlopydromeApp: App {
    @NSApplicationDelegateAdaptor(KlopydromeApplicationDelegate.self) private var appDelegate
    @State private var app = AppState()

    init() {
        // Fixes keyboard input when running as a bare SPM executable: without an
        // app bundle the process may never become the active/key-window app.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
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
        guard MiniPlayerPanelController.shared.isVisible else { return true }
        MiniPlayerPanelController.shared.activate()
        return false
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var app

    /// Token returned by `addLocalMonitorForEvents`; kept so the monitor is
    /// removed (once) when this view's lifetime ends instead of stacking.
    @State private var spaceBarMonitor: Any?

    var body: some View {
        ZStack {
            MainView()
                .onAppear { CoverArtStore.shared.configure(client: app.client, cache: app.cache) }
                .onChange(of: app.isConnected) { _, _ in
                    CoverArtStore.shared.configure(client: app.client, cache: app.cache)
                }
            // Non-sheet dim: a sheet disables the whole window chrome
            // (the toolbar items look "hidden" until it dismisses).
            // Hidden during a background auto-reconnect: credentials aren't
            // needed mid-attempt (manual login owns its own flow).
            // MainView stays mounted (toolbar registration untouched); the
            // opaque backdrop hides its unloaded tabs behind the login card.
            if !app.isLaunching && !app.isConnected && !app.isOfflineSession && !app.isBackgroundReconnecting {
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
            // Window exists by definition here: apply the transparent-titlebar
            // policy deterministically (the onAppear attempt can miss when
            // mainWindow is still nil).
            configureWindowToolbar(target: note.object as? NSWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { note in
            // SwiftUI can stomp window chrome (and re-create the toolbar) on
            // later syncs — re-apply on activation with the real window.
            if let window = note.object as? NSWindow {
                configureWindow(window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A long background strands failed covers, errored grids and a
            // dropped connection — none of which retry on their own. One
            // debounced handler revives all three (see AppState+Foreground).
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

    /// Full-screen content + transparent titlebar: the sidebar material runs up
    /// to the very top of the window (traffic lights float over it) and the
    /// unified toolbar caps the window, Finder/Music-style.
    ///
    /// The window-size floor is set HERE (AppKit level) and also enforced by
    /// `WindowMinSizeConfigurator` in `.background`. Both run because neither
    /// alone is guaranteed: this one can miss when `NSApp.mainWindow` is nil at
    /// `.onAppear` time, and the representable's `viewDidMoveToWindow` fires on
    /// every window join. Setting `minSize` in ADDITION to `contentMinSize` is
    /// deliberate: the split-view divider's drag-to-resize path can bypass the
    /// content floor, and `minSize` is the clamp AppKit applies to every frame
    /// change, no matter where it comes from.
    private func configureWindowToolbar(target: NSWindow? = nil) {
        let window = target ?? NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        guard let window else { return }
        configureWindow(window)
    }

    /// Returns `true` only for the main player window. The marker is
    /// `WindowMinSizeView`, which lives in `ContentView.background` and
    /// therefore exists solely in the player window's hierarchy — never in
    /// Settings or the mini-player panel.
    ///
    /// A style-mask check is unreliable here: `configureWindow` itself
    /// inserts `.fullSizeContentView`, so a poisoned window would keep
    /// passing the check (sticky), and system windows may carry the flag
    /// by default.
    private func isMainPlayerWindow(_ window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        return containsMainWindowMarker(content)
    }

    private func containsMainWindowMarker(_ view: NSView) -> Bool {
        if view is WindowMinSizeView { return true }
        for sub in view.subviews where containsMainWindowMarker(sub) { return true }
        return false
    }

    private func configureWindow(_ window: NSWindow) {
        // Only the main player window gets the chromeless treatment.
        // Settings keeps its default opaque background and standard title
        // bar; the mini-player panel configures its own chrome in
        // `MiniPlayerPanelController.makePanel` (including a zero min size
        // that the floor below must not override).
        guard isMainPlayerWindow(window) else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.tabbingMode = .disallowed
        // Compact player toolbar without changing unrelated windows (Settings
        // relies on normal toolbar labels and system menus).
        if let toolbar = window.toolbar {
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
        }
        // The window toolbar lives above the LCD. Its own right-click menu
        // ("Icon and Text") would shadow the LCD's NowPlaying contextMenu,
        // so clear any toolbar view's menu recursively (async: the toolbar
        // may still be installing at join time).
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
    }

    /// Music.app behaviour: space toggles play/pause unless typing in a text field
    /// or a focusable control (button, slider, menu item) is active — under Full
    /// Keyboard Access those are activated with Space, so we must not steal it.
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

/// Posted on every window join (see `WindowMinSizeView`), the first moment
/// the main window is guaranteed to exist. Lets `ContentView` apply the
/// transparent-titlebar policy deterministically — event-driven, no
/// fixed-delay guessing.
extension Notification.Name {
    static let mainWindowJoined = Notification.Name("MainWindowJoined")
}

/// Guaranteed hard floor for the window size, applied the moment this view
/// joins a window hierarchy.
///
/// `configureWindowToolbar()` runs from `.onAppear`, when `NSApp.mainWindow` /
/// `NSApp.keyWindow` can still be nil — a one-shot chance that silently misses.
/// This representable instead uses `viewDidMoveToWindow`, the AppKit hook
/// AppKit fires every time the view gains a window, so the floor is re-applied
/// no matter when (or how often) the window appears. Backs up the AppKit-level
/// `window.minSize` floor from `configureWindowToolbar`.
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

/// Applies the floor on every window join. `viewDidMoveToWindow` is the only
/// AppKit hook guaranteed to run once the view is actually inside a window —
/// `makeNSView`/`updateNSView` observe SwiftUI's update schedule, not the
/// window lifecycle.
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
        apply()
        // Pass the window itself: at join time it may not be main/key/visible
        // yet, so looking it up via NSApp races and silently misses.
        if let window {
            NotificationCenter.default.post(name: .mainWindowJoined, object: window)
        }
    }

    private func apply() {
        guard let window else { return }
        window.contentMinSize = minSize
        window.minSize = minSize
    }
}