import AppKit
import Foundation
import NavidromeClient
import os

extension AppState {
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

    func removeFromCache(_ song: SubsonicSong) async {
        guard let cache else { return }
        for suffix in candidateSuffixes(for: song) {
            let key = CacheManager.streamKey(songId: song.id, suffix: suffix)
            let fileName = cache.fileURL(for: .streams, key: key).lastPathComponent
            if cachedStreamKeys.contains(fileName) || !cachedStreamKeysSeeded {
                await cache.removeFile(for: .streams, key: key)
                cachedStreamKeys.remove(fileName)
            }
        }
        downloadedSongs.removeAll { $0.id == song.id }
        await removeOfflineSong(song)
    }

    func cancelDownload(_ song: SubsonicSong) {
        cancelledDownloads.insert(song.id)
        downloadCancellationTokens[song.id]?.withLock { $0 = true }
    }

    func downloadToCache(_ song: SubsonicSong) async throws {
        guard let cache, let url = downloadStreamURL(for: song) else {
            downloadProgress.removeValue(forKey: song.id)
            throw SubsonicError.invalidURL
        }
        let token = OSAllocatedUnfairLock<Bool>(initialState: cancelledDownloads.contains(song.id))
        downloadCancellationTokens[song.id] = token
        defer {
            downloadCancellationTokens.removeValue(forKey: song.id)
        }
        let key = CacheManager.streamKey(songId: song.id, suffix: downloadSuffix(for: song))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            downloadProgress[song.id] = 0.0
            try await TrackDownload.streamToFile(
                url: url,
                destination: temp,
                isCancelled: { @Sendable in token.withLock { $0 } },
                onProgress: { @Sendable [weak self] progress in
                    Task { @MainActor in self?.downloadProgress[song.id] = progress }
                }
            )
            try await cache.moveFile(from: temp, to: .streams, key: key)
            downloadProgress.removeValue(forKey: song.id)
            cancelledDownloads.remove(song.id)
            cachedStreamKeys.insert(cache.fileURL(for: .streams, key: key).lastPathComponent)
            await persistOfflineSong(song)
            prependDownloaded(song)

            if let client {
                Task { [weak self] in
                    guard let cache = self?.cache else { return }
                    let lyricsKey = LyricsStore.cacheKey(for: song.id)
                    if await !cache.hasFile(for: .metadata, key: lyricsKey),
                       let lyricsResult = await LyricsStore.fetchLyricsFromServer(song: song, client: client) {
                        let payload = LyricsStore.CachedLyrics(
                            syncedLines: lyricsResult.syncedLines,
                            wordsByLine: lyricsResult.wordsByLine,
                            plainText: lyricsResult.plainText
                        )
                        if let data = try? JSONEncoder().encode(payload) {
                            _ = try? await cache.write(data: data, to: .metadata, key: lyricsKey)
                        }
                    }
                }
            }
        } catch {
            downloadProgress.removeValue(forKey: song.id)
            cancelledDownloads.remove(song.id)
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    func register(downloading song: SubsonicSong) {
        downloadingSongIDs.insert(song.id)
        if !downloadingSongs.contains(where: { $0.id == song.id }) {
            downloadingSongs.append(song)
        }
        if downloadProgress[song.id] == nil {
            downloadProgress[song.id] = 0.0
        }
    }

    func unregisterDownload(from songs: [SubsonicSong]) {
        for song in songs {
            let stillInOtherTask = activeDownloadTasks.contains { task in
                task.songs.contains(where: { $0.id == song.id })
            }
            if !stillInOtherTask {
                downloadingSongIDs.remove(song.id)
                downloadingSongs.removeAll { $0.id == song.id }
                downloadProgress.removeValue(forKey: song.id)
            }
        }
    }

    func replaceDownloadedSongs(_ songs: [SubsonicSong]) {
        downloadedSongs = songs
    }

    func prependDownloaded(_ song: SubsonicSong) {
        if downloadedSongs.contains(where: { $0.id == song.id }) { return }
        downloadedSongs.insert(song, at: 0)
    }
}

enum TrackDownload {
    private static let disallowedFilenameCharacters = CharacterSet(charactersIn: "/\\:")

    static func transfer(_ remoteURL: URL, to destinationURL: URL) async {
        let log = Logger(subsystem: "app.klopydrome", category: "track-download")
        let progress = Progress()
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = destinationURL
        progress.totalUnitCount = 0
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

    static func streamToFile(
        url: URL,
        destination: URL,
        isCancelled: @escaping @Sendable () -> Bool,
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
                if isCancelled() { throw CancellationError() }
                try handle.write(contentsOf: data)
                received += Int64(data.count)
                if expected > 0 {
                    let progress = min(1, Double(received) / Double(expected))
                    let now = Date()
                    if progress == 1 || now.timeIntervalSince(lastProgressUpdate) >= 0.25 {
                        onProgress(progress)
                        lastProgressUpdate = now
                    }
                }
            }
        }
        if isCancelled() { throw CancellationError() }
    }

    static func savePanel(for song: SubsonicSong) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = "Save File As…".localized
        panel.message = "Choose a destination for the audio file.".localized
        panel.prompt = "Save".localized
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

    static func transcodeSettings(in config: ServerConfig) -> (format: String?, maxBitRate: Int)? {
        let format = config.format?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hasFormat = !(format ?? "").isEmpty
        if !hasFormat, config.maxBitRate <= 0 { return nil }
        return (hasFormat ? format : nil, max(0, config.maxBitRate))
    }

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

    static func originalFormatAccessory(transcodeAvailable: Bool)
        -> (container: NSView, checkbox: NSButton) {
        let checkbox = NSButton(checkboxWithTitle: "Save in original format".localized,
                                target: nil, action: nil)
        checkbox.state = .on
        if !transcodeAvailable {
            checkbox.isEnabled = false
            checkbox.toolTip = "Configure the transcoding codec or bitrate in Settings.".localized
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
