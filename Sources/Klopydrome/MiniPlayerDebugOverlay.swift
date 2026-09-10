import SwiftUI

/// Tiny on-screen debug HUD: shows the seek-related state variables
/// so we can see what's happening on your machine. Enable with:
///   defaults write Klopydrome debugShowPlayerState -bool YES
struct MiniPlayerDebugOverlay: View {
    let app: AppState

    var body: some View {
        let playerState = app.player
        let engine = playerState.mpvEngine
        let held = playerState.heldSeekTarget.map { String(format: "%.1f", $0) } ?? "nil"
        VStack(alignment: .leading, spacing: 1) {
            Text("heldSeekTarget=\(held)")
            Text("mpvStreamOffset=\(String(format: "%.1f", playerState.mpvStreamOffset))")
            Text("mpvSeekRestartActive=\(String(describing: playerState.mpvSeekRestartActive)) "
                + "mpvRestartStepped=\(String(describing: playerState.mpvRestartStepped))")
            Text("currentSourceIsRemoteTranscode="
                + "\(String(describing: playerState.currentSourceIsRemoteTranscode)) "
                + "isSeekable=\(String(describing: engine.isSeekable))")
            Text("duration=\(String(format: "%.1f", engine.duration)) "
                + "engineKind=\(String(describing: playerState.engineKind)) "
                + "isBuffering=\(String(describing: engine.isBuffering))")
            Text("currentTime=\(String(format: "%.1f", engine.currentTime))")
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.yellow)
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .allowsHitTesting(false)
    }
}
