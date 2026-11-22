import AppKit
import NavidromeClient
import SwiftUI

struct SelectableHeaderText: View {
    static let horizontalSafeZone: CGFloat = 6

    let text: String
    let font: NSFont
    let color: NSColor
    var lineLimit: Int?
    var onClick: (() -> Void)?

    var body: some View {
        SelectableHeaderTextRepresentable(
            text: text,
            font: font,
            color: color,
            lineLimit: lineLimit,
            onClick: onClick
        )
        .padding(.horizontal, -Self.horizontalSafeZone)
    }

    static func font(for style: NSFont.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style)
        if weight == .regular { return base }
        return NSFont.systemFont(ofSize: base.pointSize, weight: weight)
    }

    static func measuredContentSize(
        text: String,
        font: NSFont,
        lineLimit: Int?,
        proposedWidth: CGFloat?
    ) -> CGSize {
        let maxWidth: CGFloat
        if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
            maxWidth = min(proposedWidth, 10_000)
        } else {
            maxWidth = 10_000
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let options: NSString.DrawingOptions = lineLimit == 1
            ? [.usesFontLeading]
            : [.usesLineFragmentOrigin, .usesFontLeading]
        let rect = attributed.boundingRect(
            with: NSSize(width: maxWidth, height: 10_000),
            options: options
        )
        let width = min(maxWidth, ceil(rect.width) + 2)
        let height = lineLimit == 1 ? lineHeight : max(ceil(rect.height), lineHeight)
        return CGSize(width: width, height: height)
    }
}

private struct SelectableHeaderTextRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let lineLimit: Int?
    let onClick: (() -> Void)?

    func makeNSView(context: Context) -> HeaderSelectableTextView {
        let view = HeaderSelectableTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.focusRingType = .none
        view.textContainerInset = NSSize(width: SelectableHeaderText.horizontalSafeZone, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyProperties(to: view)
        return view
    }

    func updateNSView(_ nsView: HeaderSelectableTextView, context: Context) {
        applyProperties(to: nsView)
    }

    static func dismantleNSView(_ nsView: HeaderSelectableTextView, coordinator: ()) {
        nsView.removeOutsideClickMonitor()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HeaderSelectableTextView,
        context: Context
    ) -> CGSize? {
        let inset = SelectableHeaderText.horizontalSafeZone * 2
        let contentBudget = proposal.width.map { max(0, $0 - inset) }
        let content = SelectableHeaderText.measuredContentSize(
            text: text,
            font: font,
            lineLimit: lineLimit,
            proposedWidth: contentBudget
        )
        return CGSize(width: content.width + inset, height: content.height)
    }

    private func applyProperties(to view: HeaderSelectableTextView) {
        view.onClick = onClick
        view.usesStandardArrowCursor = onClick != nil
        view.preferredLineLimit = lineLimit
        if view.font != font {
            view.font = font
            view.invalidateIntrinsicContentSize()
        }
        if view.textColor != color {
            view.textColor = color
        }
        view.textContainer?.maximumNumberOfLines = lineLimit ?? 0
        view.textContainer?.lineBreakMode = lineLimit == 1 ? .byTruncatingTail : .byWordWrapping
        if view.string != text {
            view.string = text
            view.invalidateIntrinsicContentSize()
        }
    }
}

final class HeaderSelectableTextView: NSTextView {
    var onClick: (() -> Void)?
    var usesStandardArrowCursor = false
    var preferredLineLimit: Int?
    private var outsideClickMonitor: Any?

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    override var intrinsicContentSize: NSSize {
        let activeFont = font ?? .preferredFont(forTextStyle: .body)
        let content = SelectableHeaderText.measuredContentSize(
            text: string,
            font: activeFont,
            lineLimit: preferredLineLimit,
            proposedWidth: nil
        )
        return NSSize(
            width: content.width + SelectableHeaderText.horizontalSafeZone * 2,
            height: content.height
        )
    }

    override func layout() {
        super.layout()
        let inset = SelectableHeaderText.horizontalSafeZone * 2
        let textWidth = bounds.width.isFinite && bounds.width > inset ? bounds.width - inset : 10_000
        let textHeight = bounds.height.isFinite && bounds.height > 0 ? bounds.height + 4 : 10_000
        textContainer?.containerSize = NSSize(width: textWidth, height: textHeight)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeOutsideClickMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: usesStandardArrowCursor ? .arrow : .iBeam)
    }

    override func cursorUpdate(with event: NSEvent) {
        if usesStandardArrowCursor {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if usesStandardArrowCursor {
            NSCursor.arrow.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let startPoint = event.locationInWindow
        super.mouseDown(with: event)
        let hasSelection = selectedRange().length > 0
        if hasSelection {
            installOutsideClickMonitorIfNeeded()
            return
        }
        let endPoint = window?.mouseLocationOutsideOfEventStream ?? startPoint
        let moved = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        if let onClick, event.clickCount == 1, moved < 4 {
            clearSelection()
            onClick()
        } else {
            clearSelection()
        }
    }

    override func setSelectedRange(
        _ charRange: NSRange,
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        if charRange.length > 0 {
            installOutsideClickMonitorIfNeeded()
        } else if !stillSelectingFlag {
            removeOutsideClickMonitor()
        }
    }

    override func resignFirstResponder() -> Bool {
        removeOutsideClickMonitor()
        if selectedRange().length > 0 {
            super.setSelectedRange(NSRange(location: 0, length: 0), affinity: .downstream, stillSelecting: false)
        }
        return super.resignFirstResponder()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Copy".localized,
            action: #selector(copyHeaderText(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    func clearSelection() {
        removeOutsideClickMonitor()
        if selectedRange().length > 0 {
            super.setSelectedRange(NSRange(location: 0, length: 0), affinity: .downstream, stillSelecting: false)
        }
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func installOutsideClickMonitorIfNeeded() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard let window = self.window, event.window === window else {
                self.clearSelection()
                return event
            }
            let localPoint = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(localPoint) {
                self.clearSelection()
            }
            return event
        }
    }

    @objc private func copyHeaderText(_ sender: Any?) {
        let range = selectedRange()
        let value = range.length > 0 ? (string as NSString).substring(with: range) : string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
