import Foundation

/// Holds one AVFoundation retry for the MPV source currently being started.
///
/// Consuming the URL clears it, so an AVFoundation failure can never route back
/// into the same fallback path or create a retry loop.
struct MPVFailureFallback {
    private var pendingURL: URL?

    mutating func arm(for url: URL?) {
        pendingURL = url
    }

    mutating func takeURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    mutating func clear() {
        pendingURL = nil
    }
}
