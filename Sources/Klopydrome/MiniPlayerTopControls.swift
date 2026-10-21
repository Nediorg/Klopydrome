import AppKit
import NavidromeClient
import SwiftUI

struct MiniPlayerTopControls: View {
    private enum Control: Hashable {
        case lyrics
        case queue
        case volume
    }

    @Environment(AppState.self) private var app
    @State private var hoveredControl: Control?
    @State private var secondaryControlsVisible = true
    @State private var volumeBarExpanded = false
    @State private var volumeSliderVisible = false
    @State private var volumeTransitionTask: Task<Void, Never>?

    @Binding var showingVolume: Bool
    let togglePanel: (AppState.PlayerPanelTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if volumeBarExpanded {
                MatteVolumeSlider(value: Bindable(app).player.volume)
                    .frame(width: 144)
                    .opacity(volumeSliderVisible ? 1 : 0)
                    .allowsHitTesting(volumeSliderVisible)
            } else {
                secondaryControls
                    .opacity(secondaryControlsVisible ? 1 : 0)
                    .allowsHitTesting(secondaryControlsVisible)
            }

            volumeButton
        }
        .padding(.leading, volumeBarExpanded ? 12 : 3)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .matteTopControlSurface()
        .animation(.easeOut(duration: 0.14), value: volumeBarExpanded)
        .animation(.easeOut(duration: 0.09), value: volumeSliderVisible)
        .onDisappear {
            volumeTransitionTask?.cancel()
        }
    }

    private var secondaryControls: some View {
        HStack(spacing: 4) {
            panelButton(.lyrics, systemName: "quote.bubble", control: .lyrics)
            panelButton(.queue, systemName: "list.bullet", control: .queue)
            Rectangle()
                .fill(.white.opacity(0.32))
                .frame(width: 1, height: 22)
                .padding(.horizontal, 3)
        }
    }

    private var volumeButton: some View {
        Button {
            showingVolume ? dismissVolumeSlider() : presentVolumeSlider()
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(hoveredControl == .volume ? .white.opacity(0.28) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? .volume : nil }
        .help(showingVolume ? "Скрыть громкость".localized : "Громкость".localized)
        .accessibilityLabel(showingVolume ? "Скрыть громкость".localized : "Громкость".localized)
    }

    private func presentVolumeSlider() {
        volumeTransitionTask?.cancel()
        showingVolume = true
        withAnimation(.easeOut(duration: 0.07)) {
            secondaryControlsVisible = false
        }
        volumeTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                volumeBarExpanded = true
            }
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.09)) {
                volumeSliderVisible = true
            }
        }
    }

    private func dismissVolumeSlider() {
        volumeTransitionTask?.cancel()
        withAnimation(.easeOut(duration: 0.07)) {
            volumeSliderVisible = false
        }
        volumeTransitionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                volumeBarExpanded = false
            }
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                secondaryControlsVisible = true
            }
            showingVolume = false
        }
    }

    private func panelButton(
        _ panel: AppState.PlayerPanelTab,
        systemName: String,
        control: Control
    ) -> some View {
        Button {
            togglePanel(panel)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(buttonFill(for: panel, control: control), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredControl = $0 ? control : nil }
        .help(panel.title)
        .accessibilityLabel(panel.title)
    }

    private func buttonFill(for panel: AppState.PlayerPanelTab, control: Control) -> Color {
        if app.visiblePlayerPanel == panel { return AMColor.accent.opacity(0.82) }
        return hoveredControl == control ? .white.opacity(0.28) : .clear
    }

    private var volumeIcon: String {
        if app.player.volume == 0 { return "speaker.slash.fill" }
        if app.player.volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}

extension View {
    func matteTopControlSurface() -> some View {
        background {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
        }
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.32), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }
}
