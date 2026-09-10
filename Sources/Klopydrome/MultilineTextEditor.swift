import SwiftUI
import AppKit

/// A multi-line text editor whose text container has no internal insets or
/// line-fragment padding, so the caret starts exactly at the view's origin.
/// That makes an overlayed placeholder (padded identically) align with the
/// text pixel-perfectly — no guessing at AppKit's default 5pt
/// `lineFragmentPadding`. Used by the create-playlist and share sheets for
/// their description fields.
struct MultilineTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only replace when the source differs; typing flows through the
        // delegate and must not reset the caret.
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: MultilineTextEditor

        init(_ parent: MultilineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
