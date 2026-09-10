import SwiftUI
import NavidromeClient

/// Sync-correction controls for `LyricsView`: a compact timing button that
/// reveals offset/rate nudges, plus the shared corner-control button style.
/// Kept in its own file so `LyricsView.swift` stays under the lint size budget.
extension LyricsView {
    /// A small timing button stays out of the lyric text. Hovering it reveals
    /// the compact controls; clicking pins them for keyboard or precise pointer
    /// use. The content uses fixed columns rather than competing spacers, so
    /// both rows share the same visual rhythm.
    var syncAdjusterControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if isSyncAdjusterHovered || isSyncAdjusterPinned {
                syncAdjuster
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }

            LyricsCornerControlButton(
                systemName: "slider.horizontal.3",
                fill: AMColor.inspector,
                icon: hasSyncAdjustment ? AMColor.accent : AMColor.primaryText,
                showsBorder: true,
                accessibilityLabel: "Настройки синхронизации текста"
            ) {
                isSyncAdjusterPinned.toggle()
            }
        }
        .onHover { isSyncAdjusterHovered = $0 }
        .animation(.snappy(duration: 0.18), value: isSyncAdjusterHovered || isSyncAdjusterPinned)
    }

    private var syncAdjuster: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("Сдвиг".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AMColor.primaryText)
                    .frame(width: 42, alignment: .leading)
                syncStepButton(
                    systemName: "minus.circle.fill",
                    help: "Начать текст раньше (−0.25 с)"
                ) {
                    adjustSync(by: -syncStep)
                }
                Text(syncLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AMColor.secondaryText)
                    .frame(width: 48, alignment: .center)
                syncStepButton(
                    systemName: "plus.circle.fill",
                    help: "Начать текст позже (+0.25 с)"
                ) {
                    adjustSync(by: syncStep)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Темп".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AMColor.primaryText)
                    .frame(width: 42, alignment: .leading)
                syncStepButton(
                    systemName: "tortoise.fill",
                    help: "Замедлить текст: если к концу песни текст опережает музыку"
                ) {
                    adjustRate(by: -rateStep)
                }
                Text(rateLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .center)
                syncStepButton(
                    systemName: "hare.fill",
                    help: "Ускорить текст: если к концу песни текст отстаёт от музыки"
                ) {
                    adjustRate(by: rateStep)
                }
            }

            Button("Сбросить") {
                app.lyrics.timeOffsetSeconds = 0
                app.lyrics.timeRate = 1
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .opacity(hasSyncAdjustment ? 1 : 0)
            .allowsHitTesting(hasSyncAdjustment)
            .accessibilityHidden(!hasSyncAdjustment)
            .help("Вернуть сдвиг и темп по умолчанию")
        }
        .imageScale(.small)
        .foregroundStyle(AMColor.primaryText)
        .padding(8)
        .frame(width: 166)
        .background(AMColor.inspector, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AMColor.divider, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    }

    private var hasSyncAdjustment: Bool {
        app.lyrics.timeOffsetSeconds != 0 || app.lyrics.timeRate != 1
    }

    private func syncStepButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(AMColor.primaryText)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var syncLabel: String {
        let value = app.lyrics.timeOffsetSeconds
        if value == 0 { return "0.0 с" }
        return String(format: "%+.1f с", value)
    }

    private var rateLabel: String {
        String(format: "×%.3f", app.lyrics.timeRate)
    }

    /// Rate adjustment step: 1% per click. Over a 4-minute song that shifts the
    /// end of the lyrics by ~2.4 s — the typical magnitude of provider drift.
    /// Small enough to be gentle, big enough to counter drift in a few clicks.
    private var rateStep: Double { 0.01 }

    /// Rate bounds: the provider's timestamps rarely deviate beyond ±30%.
    private var minRate: Double { 0.7 }
    private var maxRate: Double { 1.3 }

    private func adjustSync(by step: Double) {
        let value = min(max(app.lyrics.timeOffsetSeconds + step, -30), 30)
        app.lyrics.timeOffsetSeconds = (value * 100).rounded() / 100
    }

    private func adjustRate(by step: Double) {
        let value = min(max(app.lyrics.timeRate + step, minRate), maxRate)
        app.lyrics.timeRate = (value * 1000).rounded() / 1000
    }
}
