import SwiftUI

struct CrossfadeToolbarIndicator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.player.isCrossfading {
            ZStack {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AMColor.accent.opacity(0.35))
                Circle()
                    .trim(from: 0, to: app.player.crossfadeStepProgress)
                    .stroke(AMColor.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 8, height: 8)
            }
            .transaction { $0.animation = nil }
            .help("Crossfade".localized)
            .accessibilityLabel("Crossfade".localized)
            .frame(width: 24, height: 30)
            .fixedSize()
            .transition(.opacity)
        }
    }
}
