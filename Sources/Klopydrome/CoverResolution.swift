import Foundation

/// Cover-art resolution requested from the server. `.high` (the ServerConfig
/// default) requests up to 1000px — sharp on Retina without wasting bandwidth.
enum CoverResolution: String, Codable, CaseIterable, Identifiable {
    case original, retina, high, medium, low
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Оригинал"
        case .retina: return "Retina"
        case .high: return "Высокое"
        case .medium: return "Среднее"
        case .low: return "Низкое"
        }
    }

    /// Discrete size buckets to prevent cache fragmentation from arbitrary fractional
    /// or window-resize-dependent pixel values.
    private static let buckets = [80, 160, 240, 360, 500, 750, 1000]

    private static func bucketed(_ pixels: Int, cap: Int) -> Int {
        let target = min(max(1, pixels), cap)
        for bucket in buckets where bucket >= target {
            return min(bucket, cap)
        }
        return target
    }

    /// Pixel size to request from the server for a given display-pixel need.
    /// `nil` sends no `size` param (server returns full resolution).
    func requestedSize(forDisplayPixels displayPixels: Int) -> Int? {
        switch self {
        case .original: return nil
        case .retina: return Self.bucketed(displayPixels, cap: 2048)
        case .high: return Self.bucketed(displayPixels, cap: 1000)
        case .medium: return Self.bucketed(displayPixels, cap: 500)
        case .low: return Self.bucketed(displayPixels, cap: 200)
        }
    }
}
