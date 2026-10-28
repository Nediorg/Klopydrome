import Foundation
import NavidromeClient

struct ServerConfig: Codable, Equatable {
    var url: String
    var username: String
    var authMode: AuthMode
    var cacheEnabled: Bool
    var maxBitRate: Int
    var serverName: String
    var format: String?
    var streamCacheLimitBytes: Int?
    var totalCacheLimitBytes: Int?
    var theme: AppTheme?
    var coverResolution: CoverResolution?
    var playbackEngine: PlaybackEngine?
    var automixEnabled: Bool?
    var automixFadeDuration: Double?
    var automixApplyToAlbums: Bool?
    var automixReplayGainEnabled: Bool?
    var replayGainMode: ReplayGainMode?
    var replayGainPreampDB: Float?
    var silenceTrimMode: SilenceTrimMode?
    var nextTrackPreloadingEnabled: Bool?
    var discordRichPresenceEnabled: Bool?
    var discordApplicationID: String?
    var discordShowPaused: Bool?
    var lyricsFontSize: LyricsFontSize?
    var lyricsAnimationMotion: LyricsAnimationMotion?
    var lyricsBlurEnabled: Bool?
    var lyricsCountdownEnabled: Bool?
    var lyricsDefaultOffset: Double?
    var autoReconnectEnabled: Bool?
    var forceOfflineMode: Bool?
    var downloadTranscoded: Bool?
    var cacheStarredSongs: Bool?
    var cacheStarredAlbums: Bool?
    var cacheStarredArtists: Bool?
    var suppressOfflinePrompts: Bool?
    var suppressOfflineActionWarning: Bool?
    var suppressPendingMutations: Bool?
    var suppressServerScanWarning: Bool?
    var adaptiveCellularDataEnabled: Bool?
}

extension ServerConfig {
    var effectivePlaybackEngine: PlaybackEngine { playbackEngine ?? .mpv }
    var effectiveAutomixEnabled: Bool { automixEnabled ?? false }
    var effectiveAutomixFadeDuration: Double {
        min(12, max(1, automixFadeDuration ?? AutomixTransitionPlanner.defaultFade))
    }
    var effectiveAutomixApplyToAlbums: Bool { automixApplyToAlbums ?? false }
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
    var effectiveLyricsFontSize: LyricsFontSize { lyricsFontSize ?? .standard }
    var effectiveLyricsAnimationMotion: LyricsAnimationMotion { lyricsAnimationMotion ?? .smooth }
    var effectiveLyricsBlurEnabled: Bool { lyricsBlurEnabled ?? true }
    var effectiveLyricsCountdownEnabled: Bool { true }
    var effectiveLyricsDefaultOffset: Double { lyricsDefaultOffset ?? 0.0 }
    var effectiveAutoReconnectEnabled: Bool { autoReconnectEnabled ?? true }
    var effectiveForceOfflineMode: Bool { forceOfflineMode ?? false }
    var effectiveDownloadTranscoded: Bool { downloadTranscoded ?? true }
    var effectiveCacheStarredSongs: Bool { cacheStarredSongs ?? false }
    var effectiveCacheStarredAlbums: Bool { cacheStarredAlbums ?? false }
    var effectiveCacheStarredArtists: Bool { cacheStarredArtists ?? false }
    var effectiveSuppressOfflinePrompts: Bool {
        get {
            suppressOfflinePrompts ?? (suppressPendingMutations ?? false)
        }
        set {
            suppressOfflinePrompts = newValue
            suppressPendingMutations = newValue
        }
    }
    var effectiveSuppressOfflineActionWarning: Bool {
        get { suppressOfflineActionWarning ?? false }
        set { suppressOfflineActionWarning = newValue }
    }
    var effectiveSuppressPendingMutations: Bool { effectiveSuppressOfflinePrompts }
    var effectiveSuppressServerScanWarning: Bool {
        suppressServerScanWarning ?? false
    }
    var effectiveAdaptiveCellularDataEnabled: Bool {
        adaptiveCellularDataEnabled ?? true
    }

    static var empty: ServerConfig {
        ServerConfig(url: "", username: "", authMode: .token,
                     cacheEnabled: true, maxBitRate: 0, serverName: "",
                     format: nil, streamCacheLimitBytes: nil, totalCacheLimitBytes: nil,
                     theme: nil, coverResolution: nil, playbackEngine: nil,
                     automixEnabled: nil, automixFadeDuration: nil,
                     automixApplyToAlbums: nil,
                     automixReplayGainEnabled: nil, replayGainMode: nil,
                     replayGainPreampDB: nil, silenceTrimMode: nil,
                     nextTrackPreloadingEnabled: nil,
                     discordRichPresenceEnabled: nil, discordApplicationID: nil,
                     discordShowPaused: nil,
                     lyricsFontSize: nil, lyricsAnimationMotion: nil,
                     lyricsBlurEnabled: nil, lyricsCountdownEnabled: nil,
                     lyricsDefaultOffset: nil,
                     autoReconnectEnabled: nil, forceOfflineMode: nil,
                     downloadTranscoded: nil,
                     cacheStarredSongs: nil, cacheStarredAlbums: nil,
                     cacheStarredArtists: nil,
                     suppressOfflinePrompts: nil,
                     suppressOfflineActionWarning: nil,
                     suppressPendingMutations: nil,
                     suppressServerScanWarning: nil,
                     adaptiveCellularDataEnabled: nil)
    }
}
