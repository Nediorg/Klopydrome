import SwiftUI

/// Retry-aware empty state for the library tabs. A genuine empty library shows
/// just the message (no retry); a failed load shows the error with the
/// "Повторить" action wired to `retry`. Callers keep their existing layout
/// (e.g. `.emptyStatePinnedToTop()`).
struct LibraryUnavailableView: View {
    let title: String
    let systemImage: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title.localized, systemImage: systemImage)
        } description: {
            Text(message.localized)
        } actions: {
            if let retry {
                Button("Повторить", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
