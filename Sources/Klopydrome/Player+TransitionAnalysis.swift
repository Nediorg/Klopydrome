import Foundation

extension Player {
    /// Starts independent edge analysis once both playback sources are known.
    /// Remote streams yield the conservative fallback immediately; cached local
    /// files are decoded off the main actor and can refine the transition.
    func scheduleTransitionAnalysis() {
        guard automix.enabled,
              let currentSourceURL = automix.currentSourceURL,
              let preloadedSourceURL = automix.preloadedSourceURL else {
            return
        }
        let outgoingURL = currentSong.flatMap { automix.onCachedTrackURLRequest?($0) }
            ?? currentSourceURL
        let incomingURL = automix.preloadedNextSong.flatMap { automix.onCachedTrackURLRequest?($0) }
            ?? preloadedSourceURL
        let nextID = automix.preloadedNextSongID
        let currentDuration = trackDuration
        let preferredFadeDuration = automix.fadeDuration
        automix.transitionAnalysisTask?.cancel()
        automix.transitionAnalysisTask = Task { [weak self] in
            async let outgoing = AutomixAudioAnalyzer.edgeProfile(for: outgoingURL)
            async let incoming = AutomixAudioAnalyzer.edgeProfile(for: incomingURL)
            let plan = AutomixTransitionPlanner.plan(
                currentDuration: currentDuration,
                outgoing: await outgoing,
                incoming: await incoming,
                preferredFadeDuration: preferredFadeDuration
            )
            guard !Task.isCancelled,
                  let self,
                  self.automix.preloadedNextSongID == nextID else {
                return
            }
            self.automix.transitionPlan = plan
        }
    }
}
