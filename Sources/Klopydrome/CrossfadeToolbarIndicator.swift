import SwiftUI

struct CrossfadeToolbarIndicator: View {
    @Environment(AppState.self) private var app
    @State private var breathing = false

    var body: some View {
        ZStack {
            if let status = app.player.crossfadeStatusText {
                Image(systemName: "circle.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AMColor.accent)
                    .scaleEffect(breathing ? 1 : 0.78)
                    .opacity(breathing ? 1 : 0.55)
                    .animation(
                        .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: breathing
                    )
                    .onAppear { breathing = true }
                    .onDisappear { breathing = false }
                    .help(Text(verbatim: status))
                    .accessibilityLabel(status)
            }
        }
        .frame(width: 26, height: 30)
        .fixedSize()
        .layoutPriority(1)
    }
}
