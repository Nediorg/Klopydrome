import Foundation

/// A single word (or spacing chunk) of a word-synced lyric line, plus the
/// second at which it starts being sung. Chunks without their own marker
/// inherit the line start time.
struct SyncedWord: Equatable {
    let text: String
    let start: Double
    /// End of the word's sung window in seconds, from the server's `cue.end`
    /// when it could be resolved. nil → the color logic falls back to the next
    /// word's start (inline-marker parsing has no explicit ends).
    let end: Double?

    init(text: String, start: Double, end: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Parses the word-level LRC convention where inline markers are embedded in
/// the line text:
///   "I <00:10.20>love <00:10.50>coding <00:10.90>here."
/// Text before the first marker inherits the line's start; every `<m:ss.xx>`
/// marker applies to the chunk that follows it (up to the next marker).
enum WordSyncParser {
    static func parse(_ value: String, lineStart: Double?) -> [SyncedWord] {
        guard value.contains("<") else {
            return [SyncedWord(text: value, start: lineStart ?? 0)]
        }
        var words: [SyncedWord] = []
        var currentStart = lineStart ?? 0
        var chunkStart = value.startIndex
        var cursor = value.startIndex
        while cursor < value.endIndex {
            if value[cursor] == "<" {
                appendChunk(String(value[chunkStart..<cursor]), start: currentStart, to: &words)
                guard let close = value[cursor...].firstIndex(of: ">") else { break }
                let marker = value[value.index(after: cursor)..<close]
                if let seconds = parseMarker(String(marker)) {
                    currentStart = seconds
                }
                chunkStart = value.index(after: close)
                cursor = chunkStart
            } else {
                cursor = value.index(after: cursor)
            }
        }
        appendChunk(String(value[chunkStart..<value.endIndex]), start: currentStart, to: &words)
        return words
    }

    /// "m:ss.xx" (or "mm:ss") → seconds; nil if malformed.
    static func parseMarker(_ marker: String) -> Double? {
        let parts = marker.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    private static func appendChunk(_ text: String, start: Double, to words: inout [SyncedWord]) {
        guard !text.isEmpty else { return }
        words.append(SyncedWord(text: text, start: start))
    }
}
