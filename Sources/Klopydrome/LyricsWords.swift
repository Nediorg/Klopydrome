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
        // Resolve explicit word ends from consecutive markers
        for idx in 0..<words.count {
            if words[idx].end == nil && idx + 1 < words.count {
                let nextStart = words[idx + 1].start
                if nextStart > words[idx].start {
                    words[idx] = SyncedWord(text: words[idx].text, start: words[idx].start, end: nextStart)
                }
            }
        }
        return words
    }

    /// "mm:ss.xx" or "hh:mm:ss.xx" -> seconds; nil if malformed.
    static func parseMarker(_ marker: String) -> Double? {
        let parts = marker.split(separator: ":")
        if parts.count == 3 {
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        } else if parts.count == 2 {
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        return nil
    }

    private static func appendChunk(_ text: String, start: Double, to words: inout [SyncedWord]) {
        guard !text.isEmpty else { return }
        words.append(SyncedWord(text: text, start: start))
    }
}

/// An atomic cluster of timed syllables belonging to a single visible word
/// (including any trailing whitespace). Ensures that words split across inline
/// markers or syllable boundaries (e.g. "surren" + "der ") wrap as an unbroken
/// atomic unit in flow layout.
struct WordCluster: Identifiable, Equatable {
    let id: Int
    let words: [SyncedWord]
    var text: String { words.map(\.text).joined() }
}

enum WordClusterBuilder {
    static func buildClusters(from words: [SyncedWord]) -> [WordCluster] {
        guard !words.isEmpty else { return [] }

        // 1. If any single SyncedWord chunk contains whitespace not just at the end,
        // split it into whitespace-separated tokens inheriting the chunk's start/end.
        var tokens: [SyncedWord] = []
        for word in words {
            let str = word.text
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains(where: { $0.isWhitespace }) {
                var current = ""
                let chars = Array(str)
                for (charIndex, char) in chars.enumerated() {
                    current.append(char)
                    if char.isWhitespace {
                        let nextIsNonWs = (charIndex + 1 < chars.count) && !chars[charIndex + 1].isWhitespace
                        if nextIsNonWs {
                            tokens.append(SyncedWord(text: current, start: word.start, end: nil))
                            current = ""
                        }
                    }
                }
                if !current.isEmpty {
                    tokens.append(SyncedWord(text: current, start: word.start, end: word.end))
                }
            } else {
                tokens.append(word)
            }
        }

        // 2. Accumulate syllables into a single word until one ends with whitespace.
        var clusters: [WordCluster] = []
        var currentSyllables: [SyncedWord] = []
        var clusterId = 0

        for token in tokens {
            currentSyllables.append(token)
            if token.text.contains(where: { $0.isWhitespace }) {
                clusters.append(WordCluster(id: clusterId, words: currentSyllables))
                clusterId += 1
                currentSyllables = []
            }
        }
        if !currentSyllables.isEmpty {
            clusters.append(WordCluster(id: clusterId, words: currentSyllables))
        }

        return clusters
    }
}
