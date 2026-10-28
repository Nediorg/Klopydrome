import SwiftUI

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
                Button("Retry".localized, action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
