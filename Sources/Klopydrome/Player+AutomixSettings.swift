import Foundation

extension Player {
    var automixEnabled: Bool { automix.enabled }
    var automixFadeDuration: Double { automix.fadeDuration }
    var automixApplyToAlbums: Bool { automix.applyToAlbums }
    var replayGainMode: ReplayGainMode { automix.replayGainMode }
    var replayGainPreampDB: Float { automix.replayGainPreampDB }
    var silenceTrimMode: SilenceTrimMode { automix.silenceTrimMode }

    /// Applies persisted crossfade preferences to both MPV contexts. Disabling
    /// crossfade cancels transition work but leaves independent next-track
    /// preloading available for ordinary gapless queue advancement.
    func configureAutomix(enabled: Bool, fadeDuration: Double, applyToAlbums: Bool = false) {
        let safeFadeDuration = min(12, max(1, fadeDuration))
        automix.enabled = enabled
        automix.fadeDuration = safeFadeDuration
        automix.applyToAlbums = applyToAlbums

        let intraAlbum = currentSong.flatMap { current in
            nextSongForPreloading.map { successor in
                Player.isIntraAlbumTransition(outgoing: current, incoming: successor, isShuffled: shuffle)
            }
        } ?? false

        if !enabled || (!applyToAlbums && intraAlbum) {
            cancelAutomixCrossfade()
            automix.transitionAnalysisTask?.cancel()
            automix.transitionAnalysisTask = nil
            automix.transitionPlan = nil
        } else if enabled && automix.transitionPlan == nil && automix.activeCrossfade == nil {
            scheduleTransitionAnalysis()
        }
    }

    /// Applies the ReplayGain correction policy to both MPV contexts. Unlike
    /// crossfade this is independent of transition planning and applies to any
    /// MPV playback.
    func configureReplayGain(mode: ReplayGainMode, preampDB: Float) {
        let safePreamp = AutomixLoudness.clampPreamp(preampDB)
        automix.replayGainMode = mode
        automix.replayGainPreampDB = safePreamp
        mpvEngine.replayGainMode = mode
        mpvEngine.replayGainPreampDB = safePreamp
        automix.preloadedMPVEngine?.replayGainMode = mode
        automix.preloadedMPVEngine?.replayGainPreampDB = safePreamp
    }

    /// Applies trailing-silence trimming to both MPV contexts.
    func configureSilenceTrim(mode: SilenceTrimMode) {
        automix.silenceTrimMode = mode
        mpvEngine.silenceTrimMode = mode
        automix.preloadedMPVEngine?.silenceTrimMode = mode
    }

    #if DEBUG
    func setEngineKindForTesting(_ kind: EngineKind) {
        engineKind = kind
    }
    #endif
}
