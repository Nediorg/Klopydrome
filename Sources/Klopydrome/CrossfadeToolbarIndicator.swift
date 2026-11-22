import NavidromeClient
import SwiftUI

private final class CrossfadeProgressTracker {
    var maxRendered: Double = 0
}

struct CrossfadeToolbarIndicator: View {
    private enum Phase: Equatable {
        case hidden
        case active(fadeInStart: CFAbsoluteTime)
        case fadingOut(start: CFAbsoluteTime, progress: Double)
    }

    private static let fadeInDuration: Double = 0.25
    private static let fadeOutDuration: Double = 0.30

    @Environment(AppState.self) private var app
    @State private var phase: Phase = .hidden
    @State private var progressTracker = CrossfadeProgressTracker()

    var body: some View {
        Group {
            switch phase {
            case .hidden:
                EmptyView()
            case .active(let fadeInStart):
                activeView(fadeInStart: fadeInStart)
            case .fadingOut(let start, let finalProgress):
                fadeOutView(start: start, finalProgress: finalProgress)
            }
        }
        .frame(width: 24, height: 30)
        .fixedSize()
        .allowsHitTesting(phase != .hidden)
        .onAppear {
            if app.player.isCrossfading {
                progressTracker.maxRendered = app.player.crossfadeTrackProgress()
                phase = .active(fadeInStart: CFAbsoluteTimeGetCurrent())
            }
        }
        .onChange(of: app.player.isCrossfading) { _, isCrossfading in
            handleCrossfadeChange(isCrossfading)
        }
        .task(id: phase) {
            guard case .fadingOut = phase else { return }
            try? await Task.sleep(for: .milliseconds(Int(Self.fadeOutDuration * 1000) + 30))
            guard !Task.isCancelled else { return }
            phase = .hidden
            progressTracker.maxRendered = 0
        }
    }

    @ViewBuilder
    private func activeView(fadeInStart: CFAbsoluteTime) -> some View {
        if Motion.enabled {
            let paused = app.player.activeCrossfade?.pausedAt != nil
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { _ in
                let now = CFAbsoluteTimeGetCurrent()
                let progress = nextMonotonicProgress(at: now)
                let opacity = CrossfadeMath.fadeOpacity(
                    elapsed: now - fadeInStart,
                    duration: Self.fadeInDuration,
                    fadingIn: true
                )
                symbol(progress: progress)
                    .opacity(opacity)
            }
        } else {
            symbol(progress: nextMonotonicProgress(at: CFAbsoluteTimeGetCurrent()))
        }
    }

    private func fadeOutView(start: CFAbsoluteTime, finalProgress: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let opacity = CrossfadeMath.fadeOpacity(
                elapsed: elapsed,
                duration: Self.fadeOutDuration,
                fadingIn: false
            )
            symbol(progress: finalProgress)
                .opacity(opacity)
        }
    }

    private func nextMonotonicProgress(at now: CFAbsoluteTime) -> Double {
        let current = app.player.crossfadeTrackProgress(at: now)
        if current > progressTracker.maxRendered {
            progressTracker.maxRendered = current
        }
        return progressTracker.maxRendered
    }

    private func handleCrossfadeChange(_ isCrossfading: Bool) {
        if isCrossfading {
            progressTracker.maxRendered = app.player.crossfadeTrackProgress()
            phase = .active(fadeInStart: CFAbsoluteTimeGetCurrent())
            return
        }
        guard Motion.enabled else {
            phase = .hidden
            progressTracker.maxRendered = 0
            return
        }
        let finalProgress = app.player.lastCrossfadeCompletedNaturally ? 1.0 : progressTracker.maxRendered
        phase = .fadingOut(start: CFAbsoluteTimeGetCurrent(), progress: finalProgress)
    }

    @ViewBuilder
    private func symbol(progress: Double) -> some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "circle.dotted.circle", variableValue: progress)
                .symbolVariableValueMode(.draw)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, AMColor.accent)
                .help("Crossfade".localized)
                .accessibilityLabel("Crossfade".localized)
                .transaction { $0.animation = nil }
        } else {
            Image(systemName: "circle.dotted.circle")
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.primary, AMColor.accent)
                .symbolEffect(.pulse, isActive: Motion.enabled && app.player.isPlaying)
                .help("Crossfade".localized)
                .accessibilityLabel("Crossfade".localized)
                .transaction { $0.animation = nil }
        }
    }
}
