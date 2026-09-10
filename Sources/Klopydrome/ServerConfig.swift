import Foundation
import NavidromeClient

struct ServerConfig: Codable, Equatable {
    var url: String
    var username: String
    var authMode: AuthMode
    var cacheEnabled: Bool
    var maxBitRate: Int
    var serverName: String
    /// Requested transcode codec for streams/downloads; nil/"" = server default.
    var format: String?
    /// Stream (audio) cache size cap in bytes; nil = CacheLimits default.
    var streamCacheLimitBytes: Int?
    /// Total cache size cap in bytes; nil = CacheLimits default.
    var totalCacheLimitBytes: Int?
    /// Appearance override; `.system` follows the OS (GUIDELINES §2).
    var theme: AppTheme?
    /// Cover-art resolution preference; `nil` = `.high`.
    var coverResolution: CoverResolution?
    /// Playback engine preference; `nil` = `.mpv` (the recommended default).
    var playbackEngine: PlaybackEngine?
    /// Automix preferences; nil preserves defaults for configurations saved before this feature.
    var automixEnabled: Bool?
    var automixFadeDuration: Double?
    var automixReplayGainEnabled: Bool?
    /// ReplayGain correction; nil migrates from the legacy
    /// `automixReplayGainEnabled` flag. Independent of crossfade.
    var replayGainMode: ReplayGainMode?
    var replayGainPreampDB: Float?
    /// Trailing-silence trimming aggressiveness; nil = `.off`.
    var silenceTrimMode: SilenceTrimMode?
    /// Prepares the queue successor in a muted MPV context before the current
    /// track ends. Nil keeps the default enabled for existing configurations.
    var nextTrackPreloadingEnabled: Bool?
    /// Opt-in Discord Rich Presence preferences for this server profile.
    var discordRichPresenceEnabled: Bool?
    var discordApplicationID: String?
    /// Whether a paused track stays visible in Discord. Defaults to true.
    var discordShowPaused: Bool?
}

extension ServerConfig {
    /// Resolved engine preference. `nil` (configs persisted before the toggle
    /// existed, or the default) falls back to the MPV engine.
    var effectivePlaybackEngine: PlaybackEngine { playbackEngine ?? .mpv }
    var effectiveAutomixEnabled: Bool { automixEnabled ?? false }
    var effectiveAutomixFadeDuration: Double {
        min(12, max(1, automixFadeDuration ?? AutomixTransitionPlanner.defaultFade))
    }
    var effectiveReplayGainMode: ReplayGainMode {
        replayGainMode ?? (automixReplayGainEnabled.map { $0 ? .track : .off } ?? .off)
    }
    var effectiveReplayGainPreampDB: Float {
        AutomixLoudness.clampPreamp(replayGainPreampDB ?? AutomixLoudness.crossfadeHeadroomDB)
    }
    var effectiveSilenceTrimMode: SilenceTrimMode { silenceTrimMode ?? .off }
    var effectiveNextTrackPreloadingEnabled: Bool { nextTrackPreloadingEnabled ?? true }
    var effectiveDiscordRichPresenceEnabled: Bool { discordRichPresenceEnabled ?? false }
    var effectiveDiscordShowPaused: Bool { discordShowPaused ?? true }

    static var empty: ServerConfig {
        ServerConfig(url: "", username: "", authMode: .token,
                     cacheEnabled: true, maxBitRate: 0, serverName: "",
                     format: nil, streamCacheLimitBytes: nil, totalCacheLimitBytes: nil,
                     theme: nil, coverResolution: nil, playbackEngine: nil,
                     automixEnabled: nil, automixFadeDuration: nil,
                     automixReplayGainEnabled: nil, replayGainMode: nil,
                     replayGainPreampDB: nil, silenceTrimMode: nil,
                     nextTrackPreloadingEnabled: nil,
                     discordRichPresenceEnabled: nil, discordApplicationID: nil,
                     discordShowPaused: nil)
    }
}
