import SwiftUI

struct CrossfadeToolbarIndicator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.player.isCrossfading {
            Image(systemName: "circle.dotted.circle", variableValue: app.player.crossfadeStepProgress)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AMColor.accent)
                .transaction { $0.animation = nil }
                .help("Crossfade".localized)
                .accessibilityLabel("Crossfade".localized)
                .frame(width: 24, height: 30)
                .fixedSize()
                .transition(.opacity)
        }
    }
}
