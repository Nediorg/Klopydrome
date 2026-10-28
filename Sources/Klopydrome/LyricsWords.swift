import Foundation

struct SyncedWord: Equatable, Codable {
    let text: String
    let start: Double
    let end: Double?

    init(text: String, start: Double, end: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }
}

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

struct WordCluster: Identifiable, Equatable {
    let id: Int
    let words: [SyncedWord]
    var text: String { words.map(\.text).joined() }
}

enum WordClusterBuilder {
    static func buildClusters(from words: [SyncedWord]) -> [WordCluster] {
        guard !words.isEmpty else { return [] }

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
