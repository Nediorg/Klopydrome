import SwiftUI
import NavidromeClient

/// A unified status card pinned to the bottom of the sidebar.
/// Adapts across background states: applying queued changes,
/// scanning the media library, and offline session mode.
struct SidebarStatusCard: View {
    @Environment(AppState.self) private var app

    enum StatusState: Equatable {
        case connecting
        case applyingChanges
        case scanningLibrary
        case offline(canReconnect: Bool)
    }

    static func resolveStatus(for app: AppState) -> StatusState? {
        if app.isFlushingOfflineMutations {
            return .applyingChanges
        } else if app.isReconnecting || app.isConnecting {
            return .connecting
        } else if app.isServerScanning {
            return .scanningLibrary
        } else if app.isOfflineSession {
            return .offline(
                canReconnect: !app.serverConfig.effectiveForceOfflineMode
            )
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
        }
    }

    private func title(for state: StatusState) -> String {
        switch state {
        case .connecting:
            return "Подключение…".localized
        case .applyingChanges:
            return "Применение изменений".localized
        case .scanningLibrary:
            return "Сканирование медиатеки…".localized
        case .offline:
            return "Офлайн-режим".localized
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
                .help("Подключиться к серверу".localized)
            } else {
                Color.clear
            }
        }
    }
}

/// Backwards compatibility alias for the sidebar status card.
typealias SidebarOfflineCard = SidebarStatusCard
