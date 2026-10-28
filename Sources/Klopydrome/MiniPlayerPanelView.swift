import NavidromeClient
import SwiftUI

/// The lower extension of the mini-player. Translucent surface matching Apple Music,
/// hosting either the lyrics or the unified playback queue panel.
struct MiniPlayerPanelView: View {
    @Environment(AppState.self) private var app

    let panel: AppState.PlayerPanelTab

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
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.25)
            }
        }
    }
}
