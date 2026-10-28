import Foundation

enum CoverResolution: String, Codable, CaseIterable, Identifiable {
    case high, medium, low
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "original", "retina", "high":
            self = .high
        case "medium":
            self = .medium
        case "low":
            self = .low
        default:
            self = .high
        }
    }

    var label: String {
        switch self {
        case .high: return "High".localized
        case .medium: return "Average".localized
        case .low: return "Data Saver".localized
        }
    }

    static let buckets = [240, 720, 1000]

    private static func bucketed(_ pixels: Int, cap: Int) -> Int {
        let target = min(max(1, pixels), cap)
        for bucket in buckets where bucket >= target {
            return min(bucket, cap)
        }
        return min(buckets.last ?? target, cap)
    }

    func requestedSize(forDisplayPixels displayPixels: Int) -> Int? {
        switch self {
        case .high: return Self.bucketed(displayPixels, cap: 1000)
        case .medium: return Self.bucketed(displayPixels, cap: 500)
        case .low: return Self.bucketed(displayPixels, cap: 240)
        }
    }

    static func candidateLargerSizes(than requested: Int) -> [Int] {
        var larger = buckets.filter { $0 > requested }
        larger.append(0) // 0 represents original full-resolution
        return larger
    }
}
