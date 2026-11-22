import SwiftUI
import NavidromeClient

struct SidebarStatusCard: View {
    @Environment(AppState.self) private var app

    private enum Metrics {
        static let rowHeight: CGFloat = 26
        static let horizontalInset: CGFloat = 8
        static let innerHorizontalPadding: CGFloat = 8
        static let topInset: CGFloat = 2
        static let bottomInset: CGFloat = 6
        static let hoverCornerRadius: CGFloat = 6
    }

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
            content(for: state)
                .padding(.horizontal, Metrics.horizontalInset)
                .padding(.top, Metrics.topInset)
                .padding(.bottom, Metrics.bottomInset)
        }
    }

    @ViewBuilder
    private func content(for state: StatusState) -> some View {
        switch state {
        case .profile(let name):
            SidebarProfileMenu(
                activeName: name,
                rowHeight: Metrics.rowHeight,
                innerHorizontalPadding: Metrics.innerHorizontalPadding,
                hoverCornerRadius: Metrics.hoverCornerRadius
            )
        default:
            statusRow(for: state)
                .padding(.horizontal, Metrics.innerHorizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.rowHeight)
        }
    }

    private func statusRow(for state: StatusState) -> some View {
        HStack(spacing: 7) {
            leadingIndicator(for: state)
                .frame(width: 14, height: 14, alignment: .center)

            Text(title(for: state))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if case .offline(let canReconnect) = state, canReconnect {
                Button {
                    Task { _ = await app.reconnect() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Connect to Server".localized)
            }
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
            EmptyView()
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
}

private struct SidebarProfileMenu: View {
    @Environment(AppState.self) private var app
    @State private var isHovering = false

    let activeName: String
    let rowHeight: CGFloat
    let innerHorizontalPadding: CGFloat
    let hoverCornerRadius: CGFloat

    var body: some View {
        Menu {
            Picker(
                "Server".localized,
                selection: Binding(
                    get: { app.activeProfileID },
                    set: { newID in
                        guard let newID,
                              newID != app.activeProfileID,
                              let profile = app.serverProfiles.first(where: { $0.id == newID }) else {
                            return
                        }
                        Task { await app.switchToProfile(profile) }
                    }
                )
            ) {
                ForEach(app.serverProfiles) { profile in
                    Text(profile.name)
                        .tag(Optional(profile.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button("Add Server…".localized) {
                app.isAddingServer = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14, height: 14, alignment: .center)

                Text(activeName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, innerHorizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .background(
                isHovering ? Color.primary.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: hoverCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovering = $0 }
    }
}
