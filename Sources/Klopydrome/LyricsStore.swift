import Foundation
import NavidromeClient
import Observation

@MainActor
@Observable
final class LyricsStore {
    var syncedLines: [SyncedLine] = [] {
        didSet {
            rebuildTimedIndex()
            displayWordsCache = [:]
        }
    }
    var wordsByLine: [Int: [SyncedWord]] = [:] {
        didSet { displayWordsCache = [:] }
    }
    @ObservationIgnored private var displayWordsCache: [Int: [SyncedWord]] = [:]
    var plainText: String?
    var isLoading = false
    var loadedForSongID: String?

    private static let timeOffsetKey = "lyricTimeOffsets"
    private static let timeRateKey = "lyricTimeRates"

    var timeOffsets: [String: Double] = [:] {
        didSet { UserDefaults.standard.set(timeOffsets, forKey: Self.timeOffsetKey) }
    }

    var timeOffsetSeconds: Double {
        get { loadedForSongID.flatMap { timeOffsets[$0] } ?? 0 }
        set { if let id = loadedForSongID { timeOffsets[id] = newValue } }
    }

    var timeRates: [String: Double] = [:] {
        didSet { UserDefaults.standard.set(timeRates, forKey: Self.timeRateKey) }
    }

    var timeRate: Double {
        get { loadedForSongID.flatMap { timeRates[$0] } ?? 1.0 }
        set { if let id = loadedForSongID { timeRates[id] = newValue } }
    }

    init() {
        timeOffsets = UserDefaults.standard.dictionary(forKey: Self.timeOffsetKey) as? [String: Double] ?? [:]
        timeRates = UserDefaults.standard.dictionary(forKey: Self.timeRateKey) as? [String: Double] ?? [:]
    }

    static func shouldApplyLoadResult(
        requestedSongID: String,
        loadedForSongID: String?,
        taskCancelled: Bool
    ) -> Bool {
        !taskCancelled && loadedForSongID == requestedSongID
    }

    struct CachedLyrics: Codable, Equatable {
        let syncedLines: [SyncedLine]
        let wordsByLine: [Int: [SyncedWord]]
        let plainText: String?
    }

    static func cacheKey(for songID: String) -> String {
        "lyrics_\(songID)"
    }

    func load(song: SubsonicSong, client: SubsonicClient?, cache: CacheManager? = nil) async {
        guard loadedForSongID != song.id else { return }
        loadedForSongID = song.id
        syncedLines = []
        wordsByLine = [:]
        plainText = nil

        let hasCachedData = await hydrateFromDiskCache(songID: song.id, cache: cache)

        guard let client else {
            isLoading = false
            return
        }

        if !hasCachedData {
            isLoading = true
        }

        defer {
            if loadedForSongID == song.id { isLoading = false }
        }

        guard let result = await Self.fetchLyricsFromServer(song: song, client: client) else { return }
        await applyServerLyrics(result, songID: song.id, hasCachedData: hasCachedData, cache: cache)
    }

    private func hydrateFromDiskCache(songID: String, cache: CacheManager?) async -> Bool {
        guard let cache else { return false }
        let key = Self.cacheKey(for: songID)
        guard let data = await cache.readData(for: .metadata, key: key),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else {
            return false
        }
        guard Self.shouldApplyLoadResult(
            requestedSongID: songID,
            loadedForSongID: loadedForSongID,
            taskCancelled: Task.isCancelled
        ) else { return false }
        self.syncedLines = cached.syncedLines
        self.wordsByLine = cached.wordsByLine
        self.plainText = cached.plainText
        return true
    }

    private func applyServerLyrics(
        _ result: CachedLyrics,
        songID: String,
        hasCachedData: Bool,
        cache: CacheManager?
    ) async {
        guard Self.shouldApplyLoadResult(
            requestedSongID: songID,
            loadedForSongID: loadedForSongID,
            taskCancelled: Task.isCancelled
        ) else { return }

        let differs = (syncedLines != result.syncedLines ||
                       wordsByLine != result.wordsByLine ||
                       plainText != result.plainText)
        if differs || !hasCachedData {
            self.syncedLines = result.syncedLines
            self.wordsByLine = result.wordsByLine
            self.plainText = result.plainText
        }

        if let cache, differs || !hasCachedData {
            if let encoded = try? JSONEncoder().encode(result) {
                _ = try? await cache.write(data: encoded, to: .metadata, key: Self.cacheKey(for: songID))
            }
        }
    }

    static func fetchLyricsFromServer(
        song: SubsonicSong,
        client: SubsonicClient
    ) async -> CachedLyrics? {
        let entries = try? await client.getLyricsBySongId(id: song.id)

        if let entry = entries?.first(where: { isTimed(entry: $0) }),
           let lines = entry.line, !lines.isEmpty {
            let synced = apply(offset: entry.offset, to: lines)
            let words = wordsByLine(from: entry, offset: entry.offset, lineCount: lines.count)
            return CachedLyrics(syncedLines: synced, wordsByLine: words, plainText: nil)
        }

        if let text = plainText(from: entries), !text.isEmpty {
            return CachedLyrics(syncedLines: [], wordsByLine: [:], plainText: text)
        }

        let fallback = try? await client.getLyrics(
            artist: song.artist ?? "",
            title: song.title ?? ""
        )
        if let text = fallback?.value, !text.isEmpty {
            let timed = LrcTextParser.parse(text)
            if !timed.isEmpty {
                return CachedLyrics(syncedLines: timed, wordsByLine: [:], plainText: nil)
            } else {
                return CachedLyrics(syncedLines: [], wordsByLine: [:], plainText: text)
            }
        }
        return nil
    }

    static func isTimed(entry: LyricsEntry) -> Bool {
        guard entry.synced ?? false else { return false }
        return entry.line?.contains(where: { $0.start != nil }) ?? false
    }

    static func plainText(from entries: [LyricsEntry]?) -> String? {
        let text = entries?
            .compactMap { $0.line }
            .flatMap { $0 }
            .compactMap { $0.value }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
        return (text?.isEmpty ?? true) ? nil : text
    }

    static func apply(offset: Double?, to lines: [SyncedLine]) -> [SyncedLine] {
        guard let offset, offset != 0 else { return lines }
        return lines.map { line in
            guard let start = line.start else { return line }
            return SyncedLine(start: start - offset, value: line.value)
        }
    }

    static func wordsByLine(from entry: LyricsEntry, offset: Double?, lineCount: Int) -> [Int: [SyncedWord]] {
        guard let cueLines = entry.cueLine, !cueLines.isEmpty else { return [:] }
        var result: [Int: [SyncedWord]] = [:]
        var seen = Set<Int>()
        for cueLine in cueLines {
            guard let index = cueLine.index, index >= 0, index < lineCount else { continue }
            guard !seen.contains(index) else { continue }
            seen.insert(index)
            guard let cues = cueLine.cue, !cues.isEmpty else { continue }
            let shift = offset ?? 0
            let words = cues.compactMap { cue -> SyncedWord? in
                guard let startMs = cue.start, let value = cue.value, !value.isEmpty else { return nil }
                return SyncedWord(
                    text: value,
                    start: (startMs - shift) / 1000,
                    end: cue.end.map { ($0 - shift) / 1000 }
                )
            }
            if !words.isEmpty { result[index] = words }
        }
        return result
    }

    func cachedDisplayWords(for index: Int) -> [SyncedWord] {
        if let hit = displayWordsCache[index] { return hit }
        let words: [SyncedWord]
        if let structured = wordsByLine[index] {
            words = structured
        } else if syncedLines.indices.contains(index) {
            let line = syncedLines[index]
            words = WordSyncParser.parse(line.value ?? "", lineStart: line.start.map { $0 / 1000 })
        } else {
            return []
        }
        displayWordsCache[index] = words
        return words
    }

    private var timedLineIndex: [(idx: Int, start: Double)] = []

    private func rebuildTimedIndex() {
        timedLineIndex = syncedLines.enumerated().compactMap { idx, line in
            guard let start = line.start else { return nil }
            return (idx, start)
        }
    }

    func activeLineIndex(at time: Double) -> Int? {
        guard !timedLineIndex.isEmpty else { return nil }
        let milliseconds = time * 1000
        var low = 0
        var high = timedLineIndex.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if timedLineIndex[mid].start <= milliseconds {
                result = timedLineIndex[mid].idx
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func reset() {
        syncedLines = []
        wordsByLine = [:]
        plainText = nil
        loadedForSongID = nil
        isLoading = false
    }
}
