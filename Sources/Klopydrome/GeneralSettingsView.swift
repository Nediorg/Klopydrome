import SwiftUI
import NavidromeClient

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var showLogout = false
    @State private var profileToDelete: ServerProfile?

    var body: some View {
        Form {
            ProfilesSettingsSection(
                profiles: app.serverProfiles,
                activeProfileID: app.activeProfileID,
                onSelect: { profile in
                    Task { await app.switchToProfile(profile) }
                },
                onDelete: { profile in
                    profileToDelete = profile
                }
            )

            accountSection

            offlineSection
        }
        .formStyle(.grouped)
        .padding()
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
        .onChange(of: app.serverConfig) { _, _ in
            app.saveSettings()
            app.refreshDiscordRichPresence()
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

// MARK: - Profiles Section

struct ProfilesSettingsSection: View {
    let profiles: [ServerProfile]
    let activeProfileID: ServerProfile.ID?
    let onSelect: (ServerProfile) -> Void
    let onDelete: (ServerProfile) -> Void

    @State private var isShowingConnectionSheet = false

    var body: some View {
        Section("Profiles".localized) {
            ForEach(profiles) { profile in
                ProfileRow(
                    profile: profile,
                    isActive: profile.id == activeProfileID,
                    onSelect: { onSelect(profile) },
                    onDelete: { onDelete(profile) }
                )
            }

            Button("Add Server…".localized) {
                isShowingConnectionSheet = true
            }
        }
        .sheet(isPresented: $isShowingConnectionSheet) {
            ServerConnectionSheet()
        }
    }
}

private struct ProfileRow: View {
    let profile: ServerProfile
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(.medium)

                Text("\(profile.username) @ \(profile.url)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            if isActive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("Active".localized)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Select".localized, action: onSelect)
                    .controlSize(.small)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete Profile".localized)
        }
        .padding(.vertical, 2)
    }
}
