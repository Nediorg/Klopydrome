import AppKit
import NavidromeClient
import SwiftUI

struct MiniPlayerPanelView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    let panel: AppState.PlayerPanelTab

    private var isDark: Bool {
        (app.appearance ?? colorScheme) == .dark
    }

    private var backdropMaterial: NSVisualEffectView.Material {
        isDark ? .hudWindow : .popover
    }

    private var backdropTint: Color {
        isDark ? Color.black.opacity(0.25) : AMColor.background.opacity(0.45)
    }

    var body: some View {
        ZStack {
            if panel == .lyrics {
                LyricsView()
                    .transition(.identity)
            } else if panel == .queue {
                QueuePanelView()
                    .transition(.identity)
            }
        }
        .animation(nil, value: panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background {
            ZStack {
                VisualEffectView(material: backdropMaterial, blendingMode: .behindWindow)
                backdropTint
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AMColor.divider)
                .frame(height: 0.5)
        }
        .preferredColorScheme(app.appearance)
    }
}
