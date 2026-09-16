import XCTest
import SwiftUI
import NavidromeClient
@testable import Klopydrome

final class PlaybackVolumeTests: XCTestCase {
    func testOutputGainUsesQuietControllableLowEnd() {
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0), 0)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 1), 1)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.05), 0.009_625, accuracy: 0.000_001)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.10), 0.0235, accuracy: 0.000_001)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 0.15), 0.041_625, accuracy: 0.000_001)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.05), 0)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.10), 0)
        XCTAssertGreaterThan(PlaybackVolume.outputGain(for: 0.15), 0)
    }

    func testMPVControlCompensatesForItsCubicGainCurve() {
        for control: Float in [0, 0.05, 0.10, 0.15, 0.5, 1] {
            let outputGain = PlaybackVolume.outputGain(for: control)
            let mpvControl = PlaybackVolume.mpvControl(forOutputGain: outputGain)
            XCTAssertEqual(mpvControl * mpvControl * mpvControl, outputGain, accuracy: 0.000_001)
        }
    }

    func testVolumeMappingsClampOutOfRangeInput() {
        XCTAssertEqual(PlaybackVolume.outputGain(for: -1), 0)
        XCTAssertEqual(PlaybackVolume.outputGain(for: 2), 1)
        XCTAssertEqual(PlaybackVolume.mpvControl(forOutputGain: -1), 0)
        XCTAssertEqual(PlaybackVolume.mpvControl(forOutputGain: 2), 1)
    }

    @MainActor
    func testInteractiveSliderTrackIsMountedInPlayerBar() {
        let app = AppState()
        let window = makeTestWindow(rootView: ContentView().environment(app))
        let toolbar = NSToolbar(identifier: "TestToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        guard let contentView = window.contentView,
              let sliderTrack = findInteractiveSliderTrackView(in: contentView) else {
            XCTFail("InteractiveSliderTrackView must be present in PlayerHeaderBar hierarchy")
            return
        }

        XCTAssertFalse(sliderTrack.mouseDownCanMoveWindow)
        XCTAssertTrue(sliderTrack.acceptsFirstMouse(for: nil))
    }

    @MainActor
    func testWindowTrafficLightsAndToolbarRemainVisible() {
        let app = AppState()
        let window = makeTestWindow(rootView: ContentView().environment(app))
        let toolbar = NSToolbar(identifier: "TestToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.layoutIfNeeded()

        guard let closeButton = window.standardWindowButton(.closeButton),
              let minButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton) else {
            XCTFail("Window traffic light buttons must exist")
            return
        }

        XCTAssertFalse(closeButton.isHidden, "Close button must not be hidden")
        XCTAssertFalse(minButton.isHidden, "Miniaturize button must not be hidden")
        XCTAssertFalse(zoomButton.isHidden, "Zoom button must not be hidden")

        let closeInWindow = closeButton.convert(closeButton.bounds, to: nil)
        XCTAssertGreaterThan(closeInWindow.minY, 650, "Traffic lights must be anchored at the top titlebar")
        XCTAssertTrue(window.toolbar?.isVisible ?? false, "Window toolbar must be visible to keep titlebar container")
    }

    @MainActor
    func testNonDraggableBackgroundMountedInAlbumDetail() {
        let app = AppState()
        struct FullWindowWithAlbum: View {
            @State var showDownloads = false

            var body: some View {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    DetailColumn(
                        showDownloads: $showDownloads,
                        isMiniPlayerVisible: false
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar { }
            }
        }

        app.openAlbumInLibrary(SubsonicAlbum(id: "test-album", title: "Burial", artist: "Burial"))

        let window = makeTestWindow(rootView: FullWindowWithAlbum().environment(app))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        guard let contentView = window.contentView,
              let nonDrag = findNonDraggable(in: contentView) else {
            XCTFail("NonDraggableNSView must be mounted when viewing AlbumDetailView")
            return
        }

        XCTAssertFalse(nonDrag.isHiddenOrHasHiddenAncestor, "NonDraggableNSView must be visible")
    }

    @MainActor
    func testNonDraggablePresentAfterNavigation() {
        let app = AppState()
        let hostingView = NSHostingView(rootView: MainView().environment(app).frame(width: 1180, height: 700))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1180, height: 700)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.titlebarSeparatorStyle = .none
        window.contentView = hostingView
        let toolbar = NSToolbar(identifier: "TestToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.layoutIfNeeded()

        guard let contentView = window.contentView,
              let ndBefore = findNonDraggable(in: contentView) else {
            XCTFail("NonDraggableNSView must exist before navigation")
            return
        }
        XCTAssertFalse(ndBefore.isHiddenOrHasHiddenAncestor, "NonDraggable must be visible before navigation")

        // Navigate to album
        app.openAlbumInLibrary(SubsonicAlbum(id: "test", title: "Burial", artist: "Burial"))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        window.layoutIfNeeded()

        guard findNonDraggable(in: contentView) != nil else {
            XCTFail("NonDraggableNSView must remain mounted after navigating to album")
            return
        }

        // Navigate back
        app.navigateBack()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        window.layoutIfNeeded()

        guard findNonDraggable(in: contentView) != nil else {
            XCTFail("NonDraggableNSView must remain mounted after navigating back")
            return
        }
    }

    @MainActor
    func testNonDraggableNSViewPresentAtVariousWidths() {
        let app = AppState()
        for width: CGFloat in [850, 960, 1180] {
            let hostingView = NSHostingView(rootView: MainView().environment(app).frame(width: width, height: 700))
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 700)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

            guard let contentView = window.contentView,
                  findNonDraggable(in: contentView) != nil else {
                XCTFail("NonDraggableNSView must exist at width \(width)")
                continue
            }
        }
    }

    @MainActor
    private func makeTestWindow(rootView: some View) -> NSWindow {
        let hostingView = NSHostingView(rootView: rootView.frame(width: 800, height: 700))
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 700)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.titlebarSeparatorStyle = .none
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    private func findNonDraggable(in view: NSView) -> NonDraggableNSView? {
        if let ndv = view as? NonDraggableNSView { return ndv }
        for sub in view.subviews {
            if let found = findNonDraggable(in: sub) { return found }
        }
        return nil
    }

    private func findInteractiveSliderTrackView(in view: NSView) -> InteractiveSliderTrackView? {
        if let istv = view as? InteractiveSliderTrackView { return istv }
        for sub in view.subviews {
            if let found = findInteractiveSliderTrackView(in: sub) { return found }
        }
        return nil
    }
}
