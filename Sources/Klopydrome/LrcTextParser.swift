import Foundation
import NavidromeClient

/// Parses raw LRC text (as returned by the classic `getLyrics` endpoint on some
/// OpenSubsonic servers, or embedded in a song) into timed lines.
///
/// Handles `[mm:ss]`, `[mm:ss.x]`, `[mm:ss.xx]` / `[mm:ss.xxx]` markers (one or
/// several per line) plus the `[offset:±N]` metadata tag, whose semantics match
/// `LyricsEntry.offset`: the effective probe time is `audio + offset`, so a
/// positive offset shifts the highlight EARLIER (baked in as `start - offset`).
/// Lines with no time marker (metadata such as `[ar:]`, `[ti:]`, blank lines)
/// are dropped. A blank line with a time marker is retained as a visual pause.
enum LrcTextParser {
    static func parse(_ text: String) -> [SyncedLine] {
        var offsetMs: Double?
        for line in text.split(separator: "\n") {
            if let offset = Self.parseOffset(from: line) {
                offsetMs = offset
            }
        }

        var timed: [SyncedLine] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let starts = Self.parseTimestamps(from: line)
            guard !starts.isEmpty else { continue }
            let value = Self.textAfterMarkers(in: line).trimmingCharacters(in: .whitespaces)
            for start in starts {
                let shifted = start - (offsetMs ?? 0)
                timed.append(SyncedLine(start: shifted, value: value))
            }
        }
        return timed
    }

    /// Extracts every leading `[mm:ss.fraction]` timestamp (in ms) from a line.
    private static func parseTimestamps(from line: Substring) -> [Double] {
        var starts: [Double] = []
        var rest = line[...]
        while let open = rest.firstIndex(of: "["), open == rest.startIndex {
            let contentStart = rest.index(after: open)
            guard let close = rest[contentStart...].firstIndex(of: "]") else { break }
            let tag = rest[contentStart..<close]
            guard let time = Self.parseTime(tag) else { break }
            starts.append(time.milliseconds)
            rest = rest[rest.index(after: close)...]
        }
        return starts
    }

    /// Parsed `mm:ss[.f]` time tag in milliseconds.
    private struct LrcTime {
        let milliseconds: Double
    }

    /// `mm:ss[.f]` -> milliseconds. Fraction may be 1–3 digits: `.8` → 800 ms,
    /// `.80` → 800 ms, `.800` → 800 ms. Returns nil when the tag is malformed.
    private static func parseTime(_ tag: Substring) -> LrcTime? {
        let parts = tag.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0]) else {
            return nil
        }
        // Whole seconds come before the fractional separator; `Double("18.80")`
        // already includes the fraction, so split it off first.
        let secondsText = parts[1]
        let fraction: Double
        let wholeSeconds: Double
        if let dot = secondsText.firstIndex(where: { $0 == "." || $0 == ":" }) {
            let fractionText = secondsText[secondsText.index(after: dot)...]
            guard let value = Double(fractionText) else { return nil }
            switch fractionText.count {
            case 1: fraction = value * 100
            case 2: fraction = value * 10
            default: fraction = value
            }
            wholeSeconds = Double(secondsText[..<dot]) ?? 0
        } else {
            fraction = 0
            wholeSeconds = Double(secondsText) ?? 0
        }
        return LrcTime(milliseconds: minutes * 60_000 + wholeSeconds * 1_000 + fraction)
    }

    private static func textAfterMarkers(in line: Substring) -> Substring {
        var rest = line[...]
        while let open = rest.firstIndex(of: "["), open == rest.startIndex {
            let contentStart = rest.index(after: open)
            guard let close = rest[contentStart...].firstIndex(of: "]") else { break }
            rest = rest[rest.index(after: close)...]
        }
        return rest
    }

    /// `[offset:±N]` (milliseconds). Returns nil for non-offset tags.
    private static func parseOffset(from line: Substring) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[offset:"), trimmed.hasSuffix("]") else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: "[offset:".count)
        let end = trimmed.index(before: trimmed.endIndex)
        return Double(trimmed[start..<end])
    }
}
