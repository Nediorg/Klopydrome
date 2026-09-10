import AppKit
import Foundation
import NavidromeClient
import os

extension AppState {
    /// Opens a native save dialog for the selected track, then downloads only
    /// that track to the location chosen by the user. This deliberately uses
    /// Subsonic's `download` endpoint rather than the offline stream cache, so
    /// it never changes cache state or expands into an album download.
    ///
    /// The panel's accessory checkbox switches between the original file
    /// (`download`, always raw bytes) and a server-transcoded copy honoring
    /// the transcode codec/bitrate from Settings (`stream` endpoint).
    func downloadTrack(_ song: SubsonicSong) {
        guard let client else { return }
        let panel = TrackDownload.savePanel(for: song)
        let transcodeSettings = TrackDownload.transcodeSettings(in: serverConfig)
        let accessory = TrackDownload.originalFormatAccessory(transcodeAvailable: transcodeSettings != nil)
        panel.accessoryView = accessory.container

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }

        let wantsOriginal = accessory.checkbox.state == .on || transcodeSettings == nil
        let remoteURL: URL?
        var destinationURL = chosenURL
        if wantsOriginal {
            // `format=raw` is load-bearing: without an explicit format Navidrome
            // may silently transcode the download (AutoTranscodeDownload /
            // player transcoding settings), and its transcode pipeline can drop
            // every tag (navidrome#5623). "raw" pins the original file bytes.
            remoteURL = client.downloadURL(songId: song.id, maxBitRate: 0, format: "raw")
        } else if let transcodeSettings {
            remoteURL = client.streamURL(songId: song.id,
                                         maxBitRate: transcodeSettings.maxBitRate,
                                         format: transcodeSettings.format,
                                         estimateContentLength: false)
            if let renamed = TrackDownload.filename(destinationURL.lastPathComponent,
                                                    applyingFormat: transcodeSettings.format) {
                destinationURL = destinationURL.deletingLastPathComponent().appendingPathComponent(renamed)
            }
        } else {
            remoteURL = nil
        }
        guard let remoteURL else { return }

        Task { await TrackDownload.transfer(remoteURL, to: destinationURL) }
    }
}

enum TrackDownload {
    private static let disallowedFilenameCharacters = CharacterSet(charactersIn: "/\\:")

    /// Streams the file to `destination` while publishing an `NSProgress`
    /// bound to the destination URL — Finder (and the Dock) render a
    /// Chrome-style progress badge on the item for the duration of the
    /// transfer, with a working cancel button.
    ///
    /// Bytes are written straight into the destination as they arrive (the
    /// file visibly grows, like a browser download); on any failure the
    /// partial file is removed so nothing half-written is left behind.
    static func transfer(_ remoteURL: URL, to destinationURL: URL) async {
        let log = Logger(subsystem: "app.klopydrome", category: "track-download")
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = destinationURL
        progress.totalUnitCount = 0
        // Finder's cancel button routes here.
        let cancelled = OSAllocatedUnfairLock<Bool>(initialState: false)
        progress.cancellationHandler = { cancelled.withLock { $0 = true } }

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destinationURL) else {
            log.error("cannot open \(destinationURL.path, privacy: .public) for writing")
            return
        }
        defer { try? handle.close() }

        progress.publish()
        defer { progress.unpublish() }
        log.info("download started → \(destinationURL.lastPathComponent, privacy: .public)")

        do {
            var written: Int64 = 0
            for try await chunk in HTTPChunkStreamer.chunks(from: remoteURL) {
                switch chunk {
                case .head(let expectedContentLength):
                    if expectedContentLength > 0 {
                        progress.totalUnitCount = expectedContentLength
                    }
                case .body(let data):
                    if cancelled.withLock({ $0 }) { throw URLError(.cancelled) }
                    try handle.write(contentsOf: data)
                    written += Int64(data.count)
                    progress.completedUnitCount = written
                }
            }
            if cancelled.withLock({ $0 }) {
                throw URLError(.cancelled)
            }
            if written == 0 {
                throw URLError(.badServerResponse)
            }
            log.info("download finished: \(written) bytes")
        } catch {
            log.error("download failed: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    /// Shared network→file transfer for offline-cache downloads. Runs entirely
    /// off the main actor (called from a nonisolated context): reads the HTTP
    /// body in native `Data` chunks (no per-byte `AsyncBytes` iteration),
    /// writes each chunk straight into `destination`, reports progress at most
    /// every 100 ms, and aborts with `CancellationError` as soon as
    /// `isCancelled` turns true.
    static func streamToFile(
        url: URL,
        destination: URL,
        isCancelled: @escaping @Sendable () async -> Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var received: Int64 = 0
        var expected: Int64 = -1
        var lastProgressUpdate = Date.distantPast
        for try await chunk in HTTPChunkStreamer.chunks(from: url) {
            switch chunk {
            case .head(let contentLength):
                expected = contentLength
            case .body(let data):
                if await isCancelled() { throw CancellationError() }
                try handle.write(contentsOf: data)
                received += Int64(data.count)
                if expected > 0 {
                    let progress = min(1, Double(received) / Double(expected))
                    let now = Date()
                    if progress == 1 || now.timeIntervalSince(lastProgressUpdate) >= 0.1 {
                        onProgress(progress)
                        lastProgressUpdate = now
                    }
                }
            }
        }
        if await isCancelled() { throw CancellationError() }
    }

    static func savePanel(for song: SubsonicSong) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = "Скачать трек"
        panel.message = "Выберите место сохранения аудиофайла."
        panel.prompt = "Скачать"
        panel.nameFieldStringValue = filename(for: song)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel
    }

    static func filename(for song: SubsonicSong) -> String {
        let sourceFilename = song.path.map { URL(fileURLWithPath: $0).lastPathComponent }
        let candidate = nonEmpty(sourceFilename) ?? fallbackFilename(for: song)
        let sanitized = sanitizeFilename(candidate)

        guard !URL(fileURLWithPath: sanitized).pathExtension.isEmpty else {
            return "\(sanitized).\(fileExtension(for: song))"
        }
        return sanitized
    }

    // MARK: Original-format checkbox

    /// Transcode codec + bitrate from Settings that a non-original download
    /// should request. `nil` when the user left the server on "original",
    /// making the panel's checkbox meaningless (it gets disabled then).
    static func transcodeSettings(in config: ServerConfig) -> (format: String?, maxBitRate: Int)? {
        let format = config.format?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasFormat = !(format ?? "").isEmpty
        if !hasFormat, config.maxBitRate <= 0 { return nil }
        return (hasFormat ? format : nil, max(0, config.maxBitRate))
    }

    /// Swaps the destination filename's extension to the requested transcode
    /// codec ("Track.flac" → "Track.opus"). Returns `nil` when no explicit
    /// codec is configured or the extension already matches.
    static func filename(_ filename: String, applyingFormat format: String?) -> String? {
        guard let trimmed = format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: filename)
        if url.pathExtension.lowercased() == trimmed { return nil }
        if url.pathExtension.isEmpty {
            return "\(filename).\(trimmed)"
        }
        return url.deletingPathExtension().appendingPathExtension(trimmed).lastPathComponent
    }

    /// The save-panel accessory row hosting the "Сохранить в оригинальном
    /// формате" switch. A plain `NSButton` (not SwiftUI) so its post-modal
    /// state can be read directly without extra bridging. Frame-based layout:
    /// the panel sizes the accessory view by its frame, and autolayout inside
    /// it would leave the container's own size ambiguous.
    static func originalFormatAccessory(transcodeAvailable: Bool)
        -> (container: NSView, checkbox: NSButton) {
        let checkbox = NSButton(checkboxWithTitle: "Сохранить в оригинальном формате",
                                target: nil, action: nil)
        checkbox.state = .on
        if !transcodeAvailable {
            checkbox.isEnabled = false
            checkbox.toolTip = "Настройте кодек или битрейт транскодинга в настройках приложения."
        }

        let size = checkbox.fittingSize
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: ceil(size.width) + 4,
                                             height: ceil(size.height) + 8))
        checkbox.frame = NSRect(x: 2,
                                y: (container.frame.height - size.height) / 2,
                                width: size.width,
                                height: size.height)
        container.autoresizingMask = [.width]
        return (container, checkbox)
    }

    private static func fallbackFilename(for song: SubsonicSong) -> String {
        let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = song.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? title : "\(artist) – \(title)"
    }

    private static func fileExtension(for song: SubsonicSong) -> String {
        let suffix = song.suffix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sanitizeFilename(suffix).isEmpty ? "audio" : sanitizeFilename(suffix)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func sanitizeFilename(_ filename: String) -> String {
        let replaced = filename.components(separatedBy: disallowedFilenameCharacters).joined(separator: "-")
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "." || trimmed == ".." ? "track" : trimmed
    }
}
