import SwiftUI
import NavidromeClient

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showLogout = false
    @State private var profileToDelete: ServerProfile?

    var body: some View {
        Form {
            if !app.serverProfiles.isEmpty {
                profilesSection
            }

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

    private var profilesSection: some View {
        Section("Profiles".localized) {
            ForEach(app.serverProfiles) { profile in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.body.weight(profile.id == app.activeProfileID ? .semibold : .regular))
                            if profile.id == app.activeProfileID {
                                Text("Active".localized)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text("\(profile.username) @ \(profile.url)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if profile.id != app.activeProfileID {
                        Button("Switch".localized) {
                            Task { await app.switchToProfile(profile) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button(role: .destructive) {
                        profileToDelete = profile
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Profile".localized)
                }
            }

            Button("Add Server…".localized) {
                app.isAddingServer = true
            }
        }
        .confirmationDialog(
            "Delete Profile?".localized,
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete".localized, role: .destructive) {
                if let profile = profileToDelete {
                    app.deleteProfile(profile)
                }
                profileToDelete = nil
            }
            Button("Cancel".localized, role: .cancel) {
                profileToDelete = nil
            }
        }
    }

    private var accountSection: some View {
        Section("Account".localized) {
            LabeledContent("Server".localized) {
                Text(app.serverConfig.url)
                    .foregroundStyle(.secondary)
            }

            Button("Sign Out".localized, role: .destructive) {
                showLogout = true
            }
            .confirmationDialog(
                "Sign out of account?".localized,
                isPresented: $showLogout,
                titleVisibility: .visible
            ) {
                Button("Sign Out".localized, role: .destructive) {
                    app.disconnect()
                }
                Button("Cancel".localized, role: .cancel) {}
            } message: {
                Text(
                    "Queue, cache, and saved password will be cleared. You will be able to connect to another server."
                        .localized
                )
            }
        }
    }

    private var isWorkOffline: Bool {
        app.serverConfig.effectiveForceOfflineMode
    }

    private var offlineSection: some View {
        Section {
            Toggle(
                "Offline Mode".localized,
                isOn: Binding(
                    get: { app.serverConfig.effectiveForceOfflineMode },
                    set: { newValue in
                        Task { await app.setWorkOffline(newValue) }
                    }
                )
            )

            Toggle(
                "Auto-reconnect".localized,
                isOn: Bindable(app).serverConfig.autoReconnectEnabled.orTrue
            )
            .disabled(isWorkOffline)

            Toggle(
                "Ask before syncing".localized,
                isOn: Binding(
                    get: { !app.serverConfig.effectiveSuppressOfflinePrompts },
                    set: { newValue in
                        app.serverConfig.effectiveSuppressOfflinePrompts = !newValue
                        app.saveSettings()
                    }
                )
            )

            LabeledContent("Status".localized) {
                Text(connectionStatusLabel)
                    .foregroundStyle(connectionStatusColor)
            }
        } header: {
            Text("Network".localized)
        }
    }

    private var connectionStatusLabel: String {
        if isWorkOffline {
            return "Offline".localized
        } else if app.isReconnecting {
            return "Connecting…".localized
        } else if app.isOfflineSession {
            return "Offline".localized
        } else {
            return "Connected to Server".localized
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
