import SwiftUI
import NavidromeClient

/// A compact status card pinned to the bottom of the sidebar when offline.
struct SidebarOfflineCard: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Офлайн-режим".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Fixed-size trailing slot: the card height must not depend on
            // whether the spinner, the reconnect button or nothing is shown.
            Group {
                if app.isReconnecting {
                    ProgressView()
                        .controlSize(.mini)
                } else if !app.serverConfig.effectiveForceOfflineMode {
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
                }
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }
}
