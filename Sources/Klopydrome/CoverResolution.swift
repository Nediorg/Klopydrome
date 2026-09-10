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

    /// Pixel size to request from the server for a given display-pixel need.
    /// `nil` sends no `size` param (server returns full resolution).
    func requestedSize(forDisplayPixels displayPixels: Int) -> Int? {
        switch self {
        case .original: return nil
        case .retina: return displayPixels
        case .high: return min(displayPixels, 1000)
        case .medium: return min(displayPixels, 500)
        case .low: return min(displayPixels, 200)
        }
    }
}
