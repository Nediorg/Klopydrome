import SwiftUI
import NavidromeClient

/// The Cmd+, Settings window: General (streaming/playback) and Cache.
struct AppSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Общие".localized, systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Поведение".localized, systemImage: "paintpalette") }
            PlaybackSettingsView()
                .tabItem { Label("Воспроизведение".localized, systemImage: "play.circle") }
            CacheSettingsView()
                .tabItem { Label("Кэш".localized, systemImage: "internaldrive") }
            AdvancedSettingsView()
                .tabItem { Label("Расширенные".localized, systemImage: "slider.horizontal.3") }
            SharesManagerView()
                .tabItem { Label("Ссылки".localized, systemImage: "link") }
        }
        .frame(width: 640, height: 500)
    }
}

private struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var app

    private var isDiscordPresenceEnabled: Bool {
        app.serverConfig.effectiveDiscordRichPresenceEnabled
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Показывать текущий трек в Discord",
                    isOn: Bindable(app).serverConfig.discordRichPresenceEnabled.orFalse
                )
                Toggle(
                    "Показывать трек на паузе",
                    isOn: Bindable(app).serverConfig.discordShowPaused.orTrue
                )
                .disabled(!isDiscordPresenceEnabled)
                TextField(
                    "Discord Application ID",
                    text: Bindable(app).serverConfig.discordApplicationID.orEmpty,
                    prompt: Text("123456789012345678")
                )
                .textContentType(.none)
                DiscordStatusRow()
            } header: {
                Text("Discord Rich Presence".localized)
            } footer: {
                Text("Для интеграции укажите Client ID приложения из Discord Developer Portal.".localized)
            }

            DebugSettingsSection()
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, _ in
            app.saveSettings()
            app.refreshDiscordRichPresence()
        }
    }
}
