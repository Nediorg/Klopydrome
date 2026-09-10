import Foundation

/// Russian plural declension + English plural, locale-aware. The Russian logic
/// mirrors the classic `skl(n, custom, lang)` rule: counts ending in 11–19 use
/// the "many" form; otherwise 1 → singular, 2–4 → paucal, rest → plural.
enum Pluralized {
    /// Whether the app is currently running in Russian.
    private static var isRussian: Bool {
        Locale.current.language.languageCode?.identifier == "ru"
    }

    static func song(_ count: Int) -> String {
        localizedNoun("plural.song", count: count)
    }

    static func album(_ count: Int) -> String {
        localizedNoun("plural.album", count: count)
    }

    static func star(_ count: Int) -> String {
        localizedNoun("plural.star", count: count)
    }

    static func track(_ count: Int) -> String {
        localizedNoun("plural.track", count: count)
    }

    private static func localizedNoun(_ key: String, count: Int) -> String {
        let form = isRussian ? russianForm(for: count) : (count == 1 ? "one" : "other")
        return L10n.text("\(key).\(form)")
    }

    /// Russian noun form for a count: singular, paucal or plural.
    private static func russianForm(for count: Int) -> String {
        let reducedCount = count % 100
        if reducedCount >= 11 && reducedCount <= 19 {
            return "many"
        }
        switch reducedCount % 10 {
        case 1: return "one"
        case 2, 3, 4: return "few"
        default: return "many"
        }
    }
}
