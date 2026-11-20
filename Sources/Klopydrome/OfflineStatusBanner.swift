import SwiftUI
import NavidromeClient

struct SidebarStatusCard: View {
    @Environment(AppState.self) private var app

    enum StatusState: Equatable {
        case connecting
        case applyingChanges
        case scanningLibrary
        case offline(canReconnect: Bool)
        case profile(name: String)
    }

    static func resolveStatus(for app: AppState) -> StatusState? {
        if app.isFlushingOfflineMutations {
            return .applyingChanges
        } else if app.isReconnecting || app.isConnecting || app.isSwitchingServer {
            return .connecting
        } else if app.isServerScanning {
            return .scanningLibrary
        } else if app.isOfflineSession {
            return .offline(
                canReconnect: !app.serverConfig.effectiveForceOfflineMode
            )
        } else if app.serverProfiles.count > 1, let profile = app.activeProfile {
            return .profile(name: profile.name)
        }
        return nil
    }

    private var currentState: StatusState? {
        Self.resolveStatus(for: app)
    }

    var body: some View {
        if let state = currentState {
            HStack(spacing: 8) {
                leadingIndicator(for: state)

                Text(title(for: state))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                trailingSlot(for: state)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
            .animation(.easeInOut(duration: 0.2), value: state)
        }
    }

    @ViewBuilder
    private func leadingIndicator(for state: StatusState) -> some View {
        switch state {
        case .connecting, .applyingChanges, .scanningLibrary:
            ProgressView()
                .controlSize(.mini)
        case .offline:
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        case .profile:
            Image(systemName: "server.rack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func title(for state: StatusState) -> String {
        switch state {
        case .connecting:
            return "Connecting…".localized
        case .applyingChanges:
            return "Applying Changes".localized
        case .scanningLibrary:
            return "Scanning media library…".localized
        case .offline:
            return "Offline Mode".localized
        case .profile(let name):
            return name
        }
    }

    @ViewBuilder
    private func trailingSlot(for state: StatusState) -> some View {
        switch state {
        case .connecting, .applyingChanges, .scanningLibrary:
            Color.clear
        case .offline(let canReconnect):
            if canReconnect {
                Button {
                    Task { _ = await app.reconnect() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Connect to Server".localized)
            } else {
                Color.clear
            }
        case .profile:
            Menu {
                ForEach(app.serverProfiles) { profile in
                    Button {
                        Task { await app.switchToProfile(profile) }
                    } label: {
                        HStack {
                            Text(profile.name)
                            if profile.id == app.activeProfileID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(profile.id == app.activeProfileID)
                }
                Divider()
                Button("Add Server…".localized) {
                    app.isAddingServer = true
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
    }
}

typealias SidebarOfflineCard = SidebarStatusCard
