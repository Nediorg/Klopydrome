import SwiftUI
import NavidromeClient

/// General application settings: server account, offline mode, and auto-reconnect preferences.
struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showLogout = false

    var body: some View {
        Form {
            accountSection

            offlineSection
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: app.serverConfig) { _, _ in
            app.saveSettings()
            app.refreshDiscordRichPresence()
        }
    }

    private var accountSection: some View {
        Section("Аккаунт") {
            LabeledContent("Сервер") {
                Text(app.serverConfig.url)
                    .foregroundStyle(.secondary)
            }

            Button("Выйти из аккаунта", role: .destructive) {
                showLogout = true
            }
            .confirmationDialog(
                "Выйти из аккаунта?",
                isPresented: $showLogout,
                titleVisibility: .visible
            ) {
                Button("Выйти", role: .destructive) {
                    app.disconnect()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                // swiftlint:disable:next line_length
                Text("Очередь, кэш и сохранённый пароль будут очищены. Вы сможете подключиться к другому серверу.".localized)
            }
        }
    }

    private var isWorkOffline: Bool {
        app.serverConfig.effectiveForceOfflineMode
    }

    private var offlineSection: some View {
        Section {
            Toggle(
                "Офлайн-режим".localized,
                isOn: Binding(
                    get: { app.serverConfig.effectiveForceOfflineMode },
                    set: { newValue in
                        Task { await app.setWorkOffline(newValue) }
                    }
                )
            )

            Toggle(
                "Автоматически переподключаться".localized,
                isOn: Bindable(app).serverConfig.autoReconnectEnabled.orTrue
            )
            .disabled(isWorkOffline)

            LabeledContent("Статус".localized) {
                Text(connectionStatusLabel)
                    .foregroundStyle(connectionStatusColor)
            }
        } header: {
            Text("Сеть".localized)
        }
    }

    private var connectionStatusLabel: String {
        if isWorkOffline {
            return "Офлайн".localized
        } else if app.isReconnecting {
            return "Подключение…".localized
        } else if app.isOfflineSession {
            return "Офлайн".localized
        } else {
            return "Подключено к серверу".localized
        }
    }

    private var connectionStatusColor: Color {
        if isWorkOffline {
            return .secondary
        } else if app.isReconnecting {
            return .secondary
        } else if app.isOfflineSession {
            return .orange
        } else {
            return .green
        }
    }
}
