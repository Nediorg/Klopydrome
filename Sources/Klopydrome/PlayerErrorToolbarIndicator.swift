import SwiftUI
import NavidromeClient

struct PlayerErrorToolbarIndicator: View {
    @Environment(AppState.self) private var app
    @State private var showPopover = false

    var body: some View {
        if let error = app.player.lastError {
            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(error)
            .accessibilityLabel(error)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Playback Error".localized)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            app.player.lastError = nil
                            showPopover = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AMColor.secondaryText)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)

                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                }
                .padding(12)
                .frame(width: 320)
            }
            .transition(.opacity)
        }
    }
}
