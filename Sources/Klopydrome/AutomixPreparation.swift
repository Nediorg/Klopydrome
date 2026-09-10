import Foundation
import NavidromeClient

/// Mutable state of the prepared automix successor. Kept outside `Player` so
/// queue and transport remain focused on the active playback path.
@MainActor
final class AutomixPreparation {
    var preloadedMPVEngine = MPVPlaybackEngine()
    var preloadedNextSong: SubsonicSong?
    var preloadedNextSongID: String?
    var isPreloadingNext = false
    var preloadTask: Task<Void, Never>?
    var onNextTrackPreloadRequest: ((SubsonicSong) -> URL?)?
    var onCachedTrackURLRequest: ((SubsonicSong) -> URL?)?
    var currentSourceURL: URL?
    var preloadedSourceURL: URL?
    var transitionPlan: AutomixTransitionPlan?
    var activeCrossfade: ActiveAutomixCrossfade?
    var transitionAnalysisTask: Task<Void, Never>?
    var enabled = true
    var fadeDuration: Double = AutomixTransitionPlanner.defaultFade
    var replayGainMode = ReplayGainMode.off
    var replayGainPreampDB: Float = AutomixLoudness.crossfadeHeadroomDB
    var silenceTrimMode = SilenceTrimMode.off
}
