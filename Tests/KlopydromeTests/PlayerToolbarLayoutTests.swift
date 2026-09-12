import AppKit
import NavidromeClient
import SwiftUI
import XCTest
@testable import Klopydrome

final class PlayerToolbarLayoutTests: XCTestCase {
    @MainActor
    func testPlayerPanelDoesNotCoverHeaderBar() {
        let app = AppState()
        let window = makeTestWindow(rootView: MainView().environment(app), width: 1000)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        // Open queue panel
        app.togglePlayerPanel(.queue)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        window.contentView?.layoutSubtreeIfNeeded()

        guard let contentView = window.contentView,
              let slider = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must remain mounted and accessible when queue panel is open")
            return
        }

        XCTAssertFalse(slider.isHiddenOrHasHiddenAncestor, "Volume slider must remain visible when queue panel is open")
        let sliderInWindow = slider.convert(slider.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(
            sliderInWindow.minY,
            window.frame.height - 54,
            "Slider must remain in the top 52pt header bar"
        )

        // Ensure hit-test at slider center hits slider directly (not obscured by PlayerPanelView)
        let sliderCenter = slider.convert(NSPoint(x: slider.bounds.midX, y: slider.bounds.midY), to: nil)
        let hitView = window.contentView?.superview?.hitTest(sliderCenter)
        XCTAssertTrue(
            hitView === slider,
            "Hit-test must return slider directly, proving PlayerPanelView does not cover it"
        )
    }

    @MainActor
    func testHeaderBarControlsPreservedAtMinimumWindowWidth() {
        let app = AppState()
        let minWidth = LayoutMetrics.windowMinWidth
        let window = makeTestWindow(rootView: MainView().environment(app), width: minWidth)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        guard let contentView = window.contentView,
              let slider = findVolumeSlider(in: contentView) else {
            XCTFail("VolumeSliderNSView must be present at minimum window width")
            return
        }

        XCTAssertFalse(slider.isHiddenOrHasHiddenAncestor)
        XCTAssertEqual(slider.bounds.width, 75, accuracy: 1.0, "Volume slider must maintain standard 75pt width")
    }

    @MainActor
    private func makeTestWindow(rootView: some View, width: CGFloat) -> NSWindow {
        let hostingView = NSHostingView(rootView: rootView.frame(width: width, height: 700))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
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
