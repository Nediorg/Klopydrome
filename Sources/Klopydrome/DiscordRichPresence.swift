import Foundation
import NavidromeClient

struct DiscordRichPresenceRequest {
    let enabled: Bool
    let applicationID: String?
    let showPaused: Bool
    let artworkURL: URL?
    let song: SubsonicSong?
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
}

@MainActor
final class DiscordRichPresence {
    private var activeApplicationID: String?

    func update(_ request: DiscordRichPresenceRequest) {
        let newApplicationID = Self.validApplicationID(request.applicationID)
        guard request.enabled,
              request.isPlaying || request.showPaused,
              let applicationID = newApplicationID,
              let song = request.song else {
            clear()
            return
        }
        if let activeApplicationID, activeApplicationID != applicationID {
            DiscordRPCTransport.clear(applicationID: activeApplicationID)
        }
        activeApplicationID = applicationID
        let activity = DiscordRichPresenceActivity(
            song: song,
            isPlaying: request.isPlaying,
            currentTime: request.currentTime,
            duration: request.duration,
            artworkURL: request.artworkURL
        )
        DiscordRPCTransport.setActivity(activity, applicationID: applicationID)
    }

    func clear() {
        guard let activeApplicationID else { return }
        DiscordRPCTransport.clear(applicationID: activeApplicationID)
        self.activeApplicationID = nil
    }

    nonisolated static func validApplicationID(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.allSatisfy(\.isNumber) else {
            return nil
        }
        return value
    }
}

struct DiscordRichPresenceTimestamps: Codable, Equatable {
    let start: Int
    let end: Int
}

struct DiscordRichPresenceAssets: Codable, Equatable {
    let largeImage: String?
    let largeText: String?

    enum CodingKeys: String, CodingKey {
        case largeImage = "large_image"
        case largeText = "large_text"
    }
}

struct DiscordRichPresenceActivity: Codable, Equatable {
    let type: Int
    let details: String
    let state: String
    let timestamps: DiscordRichPresenceTimestamps?
    let assets: DiscordRichPresenceAssets?
    let instance: Bool

    init(
        song: SubsonicSong,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        artworkURL: URL?,
        now: Date = .now
    ) {
        type = 2
        details = Self.truncated(song.displayTitle)
        state = Self.truncated(song.artist ?? "Неизвестный исполнитель")
        instance = false
        if isPlaying, duration > 0 {
            let start = Int(now.timeIntervalSince1970 - max(0, currentTime))
            timestamps = DiscordRichPresenceTimestamps(
                start: start,
                end: start + Int(duration.rounded(.up))
            )
        } else {
            timestamps = nil
        }
        let album = song.album ?? song.displayTitle
        assets = DiscordRichPresenceAssets(
            largeImage: artworkURL?.absoluteString ?? "icon",
            largeText: Self.truncated(album)
        )
    }

    /// Accept only an external HTTPS artwork URL supplied by album metadata.
    /// The URL comes from getAlbumInfo2, never from a credential-bearing stream
    /// or cover-art request built by Klopydrome.
    static func externalArtworkURL(_ rawURL: String?) -> URL? {
        guard let rawURL,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    private static func truncated(_ value: String) -> String {
        String(value.prefix(128))
    }
}
