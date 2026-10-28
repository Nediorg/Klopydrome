import SwiftUI
import NavidromeClient

extension LyricsView {
    func pauseRange(at index: Int) -> ClosedRange<Double>? {
        guard let pauseEnd = nextLyricStart(after: index),
              let pauseStart = pauseStart(at: index),
              pauseEnd > pauseStart else { return nil }
        return pauseStart...pauseEnd
    }

    private func pauseStart(at index: Int) -> Double? {
        guard let timestamp = app.lyrics.syncedLines[index].start.map({ $0 / 1000 }) else {
            return nil
        }
        guard let previousIndex = previousLyricIndex(before: index),
              let wordEnd = app.lyrics.wordsByLine[previousIndex]?.compactMap(\.end).max(),
              wordEnd >= 0, wordEnd <= timestamp else { return timestamp }
        return wordEnd
    }

    private func nextLyricStart(after index: Int) -> Double? {
        app.lyrics.syncedLines.indices.dropFirst(index + 1)
            .first { !isPause(app.lyrics.syncedLines[$0]) && app.lyrics.syncedLines[$0].start != nil }
            .flatMap { app.lyrics.syncedLines[$0].start.map { $0 / 1000 } }
    }

    private func previousLyricIndex(before index: Int) -> Int? {
        (0..<index).reversed().first { !isPause(app.lyrics.syncedLines[$0]) }
    }

    private func isPause(_ line: SyncedLine) -> Bool {
        (line.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LyricsClockSynchronizer: View {
    @Environment(AppState.self) private var app
    let onSync: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: app.player.currentTime) { _, _ in onSync() }
            .onChange(of: app.player.isPlaying) { _, _ in onSync() }
            .onChange(of: app.player.isBuffering) { _, _ in onSync() }
            .onChange(of: app.player.isLoading) { _, _ in onSync() }
            .onChange(of: app.lyrics.timeRate) { _, _ in onSync() }
            .onChange(of: app.lyrics.timeOffsetSeconds) { _, _ in onSync() }
            .onChange(of: app.serverConfig.lyricsDefaultOffset) { _, _ in onSync() }
    }
}
