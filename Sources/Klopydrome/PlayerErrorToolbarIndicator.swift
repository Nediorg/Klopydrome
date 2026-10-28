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
                VStack(alignment: .leading, spacing: 6) {
                    Label("Playback Error".localized, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: 280)
            }
            .transition(.opacity)
        }
    }
}
