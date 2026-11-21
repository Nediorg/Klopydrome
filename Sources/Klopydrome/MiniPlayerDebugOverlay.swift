import SwiftUI
import AppKit

struct MiniPlayerDebugOverlay: View {
    let app: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            playerSection
            divider
            preloadAndCrossfadeSection
        }
        .font(.system(size: 8, design: .monospaced))
        .padding(8)
        .frame(width: 380, alignment: .leading)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private var playerSection: some View {
        let player = app.player
        let engine = player.mpvEngine
        let held = player.heldSeekTarget.map { String(format: "%.1f", $0) } ?? "nil"
        let pending = player.pendingSeekTime.map { String(format: "%.1f", $0) } ?? "nil"
        let indexDesc = player.queue.indices.contains(player.currentIndex)
            ? "#\(player.currentIndex + 1)/\(player.queue.count)"
            : "none"

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("engine=\(player.engineKind == .mpv ? "mpv" : "avp")")
                    .foregroundStyle(.cyan)
                Text("queue=\(indexDesc)")
                    .foregroundStyle(.white.opacity(0.75))
                Text("state=\(playerStateText)")
                    .foregroundStyle(playerStateColor)
            }

            if let song = player.currentSong {
                let title = song.title ?? song.id
                CopyableDebugRow(key: "currentSong", value: "id=\(song.id) \"\(title)\"", copyText: "\(song.id) - \(title)")
            } else {
                Text("currentSong=nil")
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let url = player.currentSourceURL {
                let desc = url.isFileURL ? "file://...\(url.lastPathComponent)" : "http://...\(url.lastPathComponent)"
                CopyableDebugRow(key: "currentSourceURL", value: desc, copyText: url.absoluteString)
            }

            HStack(spacing: 6) {
                Text("currentTime=\(formatSec(player.currentTime))")
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
                Text("duration=\(formatSec(player.duration))")
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Text("trackDuration=\(formatSec(player.trackDuration))")
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                BoolToken(key: "isPlaying", val: player.isPlaying)
                BoolToken(key: "isLoading", val: player.isLoading)
                BoolToken(key: "isBuffering", val: player.isBuffering)
                BoolToken(key: "isCaching", val: player.isCaching)
            }

            HStack(spacing: 6) {
                BoolToken(key: "isSeekable", val: engine.isSeekable)
                BoolToken(key: "transcode", val: player.currentSourceIsRemoteTranscode)
                Text("loadGen=\(player.mpvLoadGeneration)")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("volume=\(String(format: "%.2f", player.volume))")
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Text("outputGain=\(String(format: "%.2f", player.outputGain))")
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Text("mpvVol=\(String(format: "%.2f", engine.volume))")
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("heldSeek=\(held)")
                    .foregroundStyle(player.heldSeekTarget != nil ? .orange : .white.opacity(0.7))
                    .lineLimit(1)
                BoolToken(key: "isSeekInFlight", val: player.isSeekInFlight)
                Text("pendingSeek=\(pending)")
                    .foregroundStyle(player.pendingSeekTime != nil ? .orange : .white.opacity(0.7))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("streamOffset=\(String(format: "%.1f", player.mpvStreamOffset))s")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                BoolToken(key: "restartActive", val: player.mpvSeekRestartActive)
                BoolToken(key: "restartStepped", val: player.mpvRestartStepped)
            }

            if player.hasReportedFailure || player.lastError != nil {
                HStack(spacing: 6) {
                    BoolToken(key: "hasReportedFailure", val: player.hasReportedFailure)
                    Text("lastError=\(player.lastError ?? "nil")")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
    }

    private var preloadAndCrossfadeSection: some View {
        let player = app.player
        let hasAppended = player.mpvEngine.hasAppendedTrack
        let xfLoaded = player.crossfadeEngine?.isLoaded ?? false
        let xfVol = player.crossfadeEngine?.volume ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            if let next = player.nextSongForPreloading {
                let title = next.title ?? next.id
                CopyableDebugRow(key: "nextSong", value: "id=\(next.id) \"\(title)\"", copyText: "\(next.id) - \(title)")
            } else {
                Text("nextSong=nil")
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let url = player.preloadedSourceURL {
                let desc = url.isFileURL ? "file://...\(url.lastPathComponent)" : "http://...\(url.lastPathComponent)"
                CopyableDebugRow(key: "preloadedSourceURL", value: desc, copyText: url.absoluteString)
            }

            HStack(spacing: 6) {
                BoolToken(key: "preloadingEnabled", val: player.nextTrackPreloadingEnabled)
                BoolToken(key: "appendedToMPV", val: hasAppended)
                BoolToken(key: "hasLoadedPreload", val: player.hasLoadedPreloadForNextTrack)
            }

            HStack(spacing: 6) {
                BoolToken(key: "crossfadeEnabled", val: player.crossfadeEnabled)
                BoolToken(key: "isCrossfading", val: player.isCrossfading)
                BoolToken(key: "crossfadeLoaded", val: xfLoaded)
            }

            HStack(spacing: 6) {
                Text("xfNext=\(player.crossfadeNextSongID ?? "nil")")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Text("xfStep=\(String(format: "%.2f", player.crossfadeStepProgress))")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Text("xfVol=\(String(format: "%.2f", xfVol))")
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    private var playerStateText: String {
        let player = app.player
        if player.isLoading { return "loading" }
        if player.isBuffering { return "buffering" }
        if player.isPlaying { return "playing" }
        return "paused"
    }

    private var playerStateColor: Color {
        let player = app.player
        if player.isLoading || player.isBuffering { return .orange }
        if player.isPlaying { return .green }
        return .yellow
    }

    private func formatSec(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0.0s" }
        return String(format: "%.1f", seconds) + "s"
    }
}

private struct CopyableDebugRow: View {
    let key: String
    let value: String
    let copyText: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(key + "=")
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .foregroundStyle(isHovered ? .white : .yellow)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
        }
    }
}

private struct BoolToken: View {
    let key: String
    let val: Bool

    var body: some View {
        Text("\(key)=\(val ? "true" : "false")")
            .foregroundStyle(val ? .green : .white.opacity(0.75))
            .lineLimit(1)
    }
}
