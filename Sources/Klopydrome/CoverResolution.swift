import Foundation

/// Cover-art resolution requested from the server. `.high` (the ServerConfig
/// default) requests up to 1000px — sharp on Retina without wasting bandwidth.
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
        case .high: return "Высокое".localized
        case .medium: return "Среднее".localized
        case .low: return "Экономия трафика".localized
        }
    }

    /// Discrete size buckets to prevent cache fragmentation:
    /// - 240: thumbnails (up to 120pt @2x: song rows, search pills, LCD, downloads, avatars)
    /// - 720: cards & headers (up to 360pt @2x: shelves, grids, headers, mini-player)
    /// - 1000: hero displays / maximum retina ceiling
    static let buckets = [240, 720, 1000]

    private static func bucketed(_ pixels: Int, cap: Int) -> Int {
        let target = min(max(1, pixels), cap)
        for bucket in buckets where bucket >= target {
            return min(bucket, cap)
        }
        return min(buckets.last ?? target, cap)
    }

    /// Pixel size to request from the server for a given display-pixel need.
    func requestedSize(forDisplayPixels displayPixels: Int) -> Int? {
        switch self {
        case .high: return Self.bucketed(displayPixels, cap: 1000)
        case .medium: return Self.bucketed(displayPixels, cap: 500)
        case .low: return Self.bucketed(displayPixels, cap: 240)
        }
    }

    /// Candidate sizes larger than `requested` (in ascending order of size, with 0/original last)
    /// to check on disk before falling back to network fetch.
    static func candidateLargerSizes(than requested: Int) -> [Int] {
        var larger = buckets.filter { $0 > requested }
        larger.append(0) // 0 represents original full-resolution
        return larger
    }
}
