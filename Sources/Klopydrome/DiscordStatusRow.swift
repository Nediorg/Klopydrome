import SwiftUI

/// A compact status row for the Discord Rich Presence settings section. Kept in
/// its own file so `AppSettingsView` stays under the SwiftLint file-length
/// threshold while the connection state remains visible in Settings.
struct DiscordStatusRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        LabeledContent("Статус") {
            Text(app.discordConnectionStatus.label.localized)
                .foregroundStyle(statusColor)
        }
        .help(
            "Текущее состояние соединения с Discord. Если активности нет, "
                + "проверьте, что Discord запущен и Application ID верный."
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
