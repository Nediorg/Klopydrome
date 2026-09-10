import Foundation
import NavidromeClient

extension SmartQuery {
    /// Evaluate the query predicate against a single song (ignores sort/limit).
    func matches(_ song: SubsonicSong) -> Bool {
        root.matches(song)
    }
}

extension JSONValue {
    /// Human-readable form of a JSON value (for the rule summary line).
    var displayText: String {
        switch self {
        case .string(let text): return text
        case .number(let value): return value.truncatedString
        case .bool(let isOn): return isOn ? "да" : "нет"
        case .array(let items): return items.map(\.displayText).joined(separator: " … ")
        }
    }

    /// Numeric value when the JSON value is a number (nil otherwise).
    var asNumber: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}

/// Parsed date used for `before`/`after`/`inTheLast` comparisons.
/// Shared formatter — `isoDay` is called per song during smart-playlist
/// evaluation (up to 10k songs), so a per-call `DateFormatter` alloc is
/// measurably expensive.
private let isoDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

private func isoDay(_ value: String) -> Date? {
    let date = String(value.prefix(10))
    return isoDayFormatter.date(from: date)
}

extension QueryOperator {
    /// Evaluate a rule against (field value, expected value). `actual == nil`
    /// means the field had no value for the song; `isMissing`/`isPresent` are
    /// the only operators that match on that.
    func matches(actual: QueryValue?, expected: QueryValue?) -> Bool {
        switch self {
        case .isMissing:
            return actual?.isEmpty != false
        case .isPresent:
            return actual?.isEmpty == false
        default:
            break
        }

        // Rules whose value the local model cannot evaluate (custom tags,
        // album/artist annotations, playlists) never match locally — the server
        // is the authority for those. Keep local playlists well-defined.
        guard let actual else { return false }
        return relSatisfied(actual: actual, expected: expected)
    }

    /// Compares an actual vs expected value for the relational operators.
    private func relSatisfied(actual: QueryValue, expected: QueryValue?) -> Bool {
        switch self {
        case .contains, .notContains: return containsText(actual, expected)
        case .startsWith, .endsWith: return affixText(actual, expected)
        case .is_, .isNot: return equalValue(actual, expected)
        case .gt, .gte, .lt, .lte: return orderedNumeric(actual, expected)
        case .inTheRange: return inNumericRange(actual, expected)
        case .before, .after: return orderedDay(actual, expected)
        case .inTheLast, .notInTheLast: return recentDays(actual, expected)
        case .inPlaylist, .notInPlaylist: return false
        case .isMissing, .isPresent: return false
        }
    }

    private func containsText(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        let needle = expected?.displayText ?? ""
        guard !needle.isEmpty else { return false }
        let hit = actual.displayText.localizedLowercase.contains(needle.localizedLowercase)
        return self == .contains ? hit : !hit
    }

    private func affixText(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        let affix = expected?.text ?? ""
        guard !affix.isEmpty else { return false }
        let haystack = actual.displayText.localizedLowercase
        let lowered = affix.localizedLowercase
        return self == .startsWith ? haystack.hasPrefix(lowered) : haystack.hasSuffix(lowered)
    }

    private func equalValue(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        let hit = actual == expected
        return self == .is_ ? hit : !hit
    }

    private func orderedNumeric(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        guard let actualNumber = actual.number, let expectedNumber = expected?.number else { return false }
        switch self {
        case .gt: return actualNumber > expectedNumber
        case .gte: return actualNumber >= expectedNumber
        case .lt: return actualNumber < expectedNumber
        case .lte: return actualNumber <= expectedNumber
        default: return false
        }
    }

    private func inNumericRange(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        guard let range = expected?.range, range.count == 2,
              let low = range[0].asNumber, let high = range[1].asNumber,
              let actualNumber = actual.number else { return false }
        return actualNumber >= low && actualNumber <= high
    }

    private func orderedDay(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        guard let actualText = actual.text, let expectedText = expected?.text,
              let actualDay = isoDay(actualText), let expectedDay = isoDay(expectedText) else { return false }
        return self == .before ? actualDay < expectedDay : actualDay > expectedDay
    }

    private func recentDays(_ actual: QueryValue, _ expected: QueryValue?) -> Bool {
        guard let actualText = actual.text, let day = isoDay(actualText),
              let days = expected?.number, days > 0 else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Int(days), to: Date()) ?? Date()
        let recent = day > cutoff
        return self == .inTheLast ? recent : !recent
    }
}
