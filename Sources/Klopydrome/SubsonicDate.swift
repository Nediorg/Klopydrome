import Foundation

enum SubsonicDate {
    static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let isoFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let formattedCache = NSCache<NSString, NSString>()

    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return Self.iso.date(from: iso) ?? Self.isoFallback.date(from: iso)
    }

    static func longDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let nsKey = iso as NSString
        if let cached = formattedCache.object(forKey: nsKey) {
            return cached as String
        }
        guard let date = parse(iso) else { return nil }
        let formatted = Self.display.string(from: date)
        formattedCache.setObject(formatted as NSString, forKey: nsKey)
        return formatted
    }
}
