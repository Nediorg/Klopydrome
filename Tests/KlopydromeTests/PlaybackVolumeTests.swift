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
    func testToolbarVolumeSliderRejectsWindowDraggingAndAdjustsVolume() {
        let (window, slider) = makePlayerBarWindow()
        guard let slider else {
            XCTFail("VolumeSliderNSView not found in PlayerHeaderBar hierarchy")
            return
        }

        XCTAssertFalse(slider.mouseDownCanMoveWindow, "VolumeSliderNSView must disallow window dragging")
        XCTAssertTrue(slider.acceptsFirstMouse(for: nil), "VolumeSliderNSView must accept first mouse click")

        let sliderCenterInWindow = slider.convert(NSPoint(x: slider.bounds.midX, y: slider.bounds.midY), to: nil)
        let hitView = window.contentView?.superview?.hitTest(sliderCenterInWindow)
        XCTAssertTrue(hitView === slider, "Hit-test at slider center must return VolumeSliderNSView directly")

        let trackInset: CGFloat = 6
        let trackWidth = slider.bounds.width - (trackInset * 2)
        let halfPoint = slider.convert(NSPoint(x: trackInset + trackWidth * 0.5, y: slider.bounds.midY), to: nil)

        let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: halfPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        )!
        window.sendEvent(downEvent)
        XCTAssertEqual(slider.value, 0.5, accuracy: 0.05, "Slider value should be ~0.5 after middle click")
    }

    @MainActor
    func testToolbarVolumeSliderStaysInHierarchy() {
        let (window, slider) = makePlayerBarWindow()
        guard let slider else {
            XCTFail("VolumeSliderNSView not found in PlayerHeaderBar hierarchy")
            return
        }

        XCTAssertFalse(slider.mouseDownCanMoveWindow, "VolumeSliderNSView must disallow window dragging")
        XCTAssertTrue(slider.acceptsFirstMouse(for: nil), "VolumeSliderNSView must accept first mouse click")

        let sliderCenter = slider.convert(NSPoint(x: slider.bounds.midX, y: slider.bounds.midY), to: nil)
        let hitView = window.contentView?.superview?.hitTest(sliderCenter)
        XCTAssertTrue(hitView === slider, "Hit-test must return VolumeSliderNSView directly")
    }

    @MainActor
    func testWindowTrafficLightsAndToolbarRemainVisible() {
        let (window, _) = makePlayerBarWindow()
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
    func testPlayerHeaderBarAndVolumeSliderInAlbumDetail() {
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
              let slider = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must be mounted when viewing AlbumDetailView")
            return
        }

        XCTAssertFalse(slider.isHiddenOrHasHiddenAncestor, "VolumeSliderNSView must be visible")
        let sliderInWindow = slider.convert(slider.bounds, to: nil)
        let minExpectedY = window.frame.height - 54
        XCTAssertGreaterThanOrEqual(sliderInWindow.minY, minExpectedY, "Slider must be in top 52pt header")
        XCTAssertLessThanOrEqual(sliderInWindow.maxY, window.frame.height, "Slider must stay in window")
    }

    @MainActor
    func testRealAppAlbumNavigation() {
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
              let sliderBefore = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must exist before navigation")
            return
        }
        XCTAssertFalse(sliderBefore.isHiddenOrHasHiddenAncestor, "Slider must be visible before navigation")
        let frameBefore = sliderBefore.convert(sliderBefore.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(frameBefore.minY, window.frame.height - 54)

        // Navigate to album
        app.openAlbumInLibrary(SubsonicAlbum(id: "test", title: "Burial", artist: "Burial"))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        window.layoutIfNeeded()

        guard let sliderAfter = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must remain mounted after navigating to album")
            return
        }
        XCTAssertFalse(sliderAfter.isHiddenOrHasHiddenAncestor, "Slider must be visible after navigating to album")
        let frameAfter = sliderAfter.convert(sliderAfter.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(frameAfter.minY, window.frame.height - 54)

        // Navigate back
        app.navigateBack()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        window.layoutIfNeeded()

        guard let sliderAfterBack = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must remain mounted after navigating back")
            return
        }
        XCTAssertFalse(sliderAfterBack.isHiddenOrHasHiddenAncestor, "Slider must be visible after navigating back")
    }
    @MainActor
    private func makePlayerBarWindow() -> (NSWindow, VolumeSliderNSView?) {
        let app = AppState()
        let window = makeTestWindow(rootView: ContentView().environment(app))
        let toolbar = NSToolbar(identifier: "TestToolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.layoutIfNeeded()
        return (window, window.contentView.flatMap { findVolumeSlider(in: $0) })
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

    private func findVolumeSlider(in view: NSView) -> VolumeSliderNSView? {
        if let slider = view as? VolumeSliderNSView { return slider }
        for sub in view.subviews {
            if let found = findVolumeSlider(in: sub) { return found }
        }
        return nil
    }
}
