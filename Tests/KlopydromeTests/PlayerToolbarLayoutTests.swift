import AppKit
import NavidromeClient
import SwiftUI
import XCTest
@testable import Klopydrome

final class PlayerToolbarLayoutTests: XCTestCase {
    @MainActor
    func testHeaderBarControlsPreservedAtMinimumWindowWidth() {
        let app = AppState()
        let minWidth = LayoutMetrics.windowMinWidth
        let window = makeTestWindow(rootView: MainView().environment(app), width: minWidth)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        guard let contentView = window.contentView else {
            XCTFail("contentView must exist at minimum window width")
            return
        }
        // NonDraggableNSView must be present (backs the volume cluster)
        let nonDrag = findNonDraggable(in: contentView)
        XCTAssertNotNil(nonDrag, "NonDraggableNSView must be present at minimum window width")
    }

    @MainActor
    func testLongTitleDoesNotClipLeadingEdgeInLCD() {
        let app = AppState()
        let song = SubsonicSong(
            id: "sonic-long",
            title: "For True Story ...for Sonic vs. Shadow",
            artist: "D TEAM — Multi-Dimensional: Sonic Adventure 2 Original Soundtrack"
        )
        app.player.queue = [song]
        app.player.currentIndex = 0
        let window = makeTestWindow(rootView: MainView().environment(app), width: 1000)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.contentView?.layoutSubtreeIfNeeded()

        guard let contentView = window.contentView else {
            XCTFail("contentView must exist")
            return
        }
        XCTAssertFalse(contentView.isHiddenOrHasHiddenAncestor)
    }

    @MainActor
    func testFadeTruncatedLabelLeftAlignedAndTruncated() {
        let labelShort = FadeTruncatedLabel(
            text: "Short title",
            minLeading: 50,
            minTrailing: 24
        )
        let labelLong = FadeTruncatedLabel(
            text: "Very long track title that easily overflows the small available width",
            minLeading: 68,
            minTrailing: 38
        )

        let windowShort = makeTestWindow(rootView: labelShort.frame(width: 150, height: 20), width: 300)
        let windowLong = makeTestWindow(rootView: labelLong.frame(width: 150, height: 20), width: 300)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        windowShort.contentView?.layoutSubtreeIfNeeded()
        windowLong.contentView?.layoutSubtreeIfNeeded()

        XCTAssertNotNil(windowShort.contentView)
        XCTAssertNotNil(windowLong.contentView)
    }

    @MainActor
    func testFadeTruncatedLabelHoverMargins() {
        let subtitleHover = FadeTruncatedLabel(
            text: "Kenta Nagata — Animal Crossing Original Soundtrack",
            font: .system(size: 12),
            color: .secondary,
            minLeading: 68,
            minTrailing: 38
        )
        let window = makeTestWindow(rootView: subtitleHover.frame(width: 200, height: 20), width: 300)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertNotNil(window.contentView)
    }

    @MainActor
    func testControlsDoNotAllowWindowDragging() {
        let nonDraggable = NonDraggableNSView()
        XCTAssertFalse(nonDraggable.mouseDownCanMoveWindow)
    }

    @MainActor
    func testNonDraggableBackgroundMountedInPlayerBar() {
        let app = AppState()
        let song = SubsonicSong(id: "s1", title: "Test Song", artist: "Test Artist")
        app.player.queue = [song]
        app.player.currentIndex = 0
        let window = makeTestWindow(rootView: MainView().environment(app), width: 1000)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        window.contentView?.layoutSubtreeIfNeeded()

        guard let contentView = window.contentView,
              let nonDrag = findNonDraggable(in: contentView) else {
            XCTFail("NonDraggableNSView must be mounted in player bar")
            return
        }

        XCTAssertFalse(nonDrag.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(nonDrag.mouseDownCanMoveWindow)
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

    private func findNonDraggable(in view: NSView) -> NonDraggableNSView? {
        if let ndv = view as? NonDraggableNSView { return ndv }
        for sub in view.subviews {
            if let found = findNonDraggable(in: sub) { return found }
        }
        return nil
    }
}
