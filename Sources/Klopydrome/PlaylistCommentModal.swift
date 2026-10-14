import SwiftUI

/// Centered in-window modal card presenting the full description or comment of a playlist.
struct PlaylistCommentModal: View {
    let title: String
    let comment: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.title3.bold())
                    .lineLimit(2)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Закрыть".localized)
                .accessibilityLabel("Закрыть".localized)
            }

            ScrollView {
                Text(comment)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)

            HStack {
                Spacer()
                Button("Закрыть".localized) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
