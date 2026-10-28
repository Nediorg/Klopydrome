import SwiftUI

struct DiscordStatusRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        LabeledContent("Status".localized) {
            Text(app.discordConnectionStatus.label.localized)
                .foregroundStyle(statusColor)
        }
        .help(
            "Current Discord connection status. If there is no activity, "
                + "check that Discord is running and the Application ID is correct.".localized
        )
    }

    private var statusColor: Color {
        switch app.discordConnectionStatus {
        case .connected: return .green
        case .idle: return .secondary
        default: return .red
        }
    }
}
