import SwiftUI
import NavidromeClient

struct AppSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General".localized, systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Look and Feel".localized, systemImage: "paintpalette") }
            PlaybackSettingsView()
                .tabItem { Label("Playback".localized, systemImage: "play.circle") }
            CacheSettingsView()
                .tabItem { Label("Cache".localized, systemImage: "internaldrive") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced".localized, systemImage: "slider.horizontal.3") }
            SharesManagerView()
                .tabItem { Label("Links".localized, systemImage: "link") }
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
                    "Show current track in Discord".localized,
                    isOn: Bindable(app).serverConfig.discordRichPresenceEnabled.orFalse
                )
                Toggle(
                    "Show paused track in Discord".localized,
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
                Text("Enter the Client ID of your application from the Discord Developer Portal.".localized)
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
