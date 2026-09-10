import AppKit
import SwiftUI

/// A transparent native tooltip view that occupies only the downloads button.
/// `NSView.addToolTip` binds the hint to this exact rectangle instead of the
/// wider SwiftUI host created for the principal toolbar item.
struct DownloadsTooltipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> DownloadsTooltipView {
        DownloadsTooltipView(text: text)
    }

    func updateNSView(_ nsView: DownloadsTooltipView, context: Context) {
        nsView.updateText(text)
    }
}

final class DownloadsTooltipView: NSView, NSViewToolTipOwner {
    private var text: String
    private var tooltipTag: NSView.ToolTipTag = 0
    private var tooltipRect: NSRect = .zero

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        registerTooltipIfNeeded()
    }

    func updateText(_ text: String) {
        guard self.text != text else { return }
        self.text = text
        resetTooltip()
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        text
    }

    private func registerTooltipIfNeeded() {
        guard !bounds.isEmpty, tooltipRect != bounds else { return }
        resetTooltip()
        tooltipRect = bounds
        tooltipTag = addToolTip(bounds, owner: self, userData: nil)
    }

    private func resetTooltip() {
        if tooltipTag != 0 {
            removeToolTip(tooltipTag)
            tooltipTag = 0
        }
        tooltipRect = .zero
    }
}
