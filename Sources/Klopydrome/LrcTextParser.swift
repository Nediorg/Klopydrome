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
        var rawLines: [(starts: [Double], text: Substring)] = []

        text.enumerateLines { line, _ in
            let lineSub = line[...]
            if let offset = Self.parseOffset(from: lineSub) {
                offsetMs = offset
                return
            }
            let starts = Self.parseTimestamps(from: lineSub)
            guard !starts.isEmpty else { return }
            let value = Self.textAfterMarkers(in: lineSub)
            rawLines.append((starts, value))
        }

        let effectiveOffset = offsetMs ?? 0
        var timed: [SyncedLine] = []
        timed.reserveCapacity(rawLines.count)
        for (starts, value) in rawLines {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            for start in starts {
                timed.append(SyncedLine(start: start - effectiveOffset, value: trimmed))
            }
        }
        timed.sort { ($0.start ?? 0) < ($1.start ?? 0) }
        return timed
    }

    /// Extracts every leading `[mm:ss.fraction]` or `[hh:mm:ss.fraction]` timestamp (in ms) from a line.
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

    /// Parsed time tag in milliseconds.
    private struct LrcTime {
        let milliseconds: Double
    }

    /// `[hh:]mm:ss[.f]` -> milliseconds. Returns nil when the tag is malformed.
    private static func parseTime(_ tag: Substring) -> LrcTime? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        let hours: Double
        let minutes: Double
        let secondsText: Substring
        if parts.count == 3 {
            guard let hrs = Double(parts[0]), let mins = Double(parts[1]) else { return nil }
            hours = hrs
            minutes = mins
            secondsText = parts[2]
        } else if parts.count == 2 {
            hours = 0
            guard let mins = Double(parts[0]) else { return nil }
            minutes = mins
            secondsText = parts[1]
        } else {
            return nil
        }
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
        let totalMs = hours * 3_600_000 + minutes * 60_000 + wholeSeconds * 1_000 + fraction
        return LrcTime(milliseconds: totalMs)
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
