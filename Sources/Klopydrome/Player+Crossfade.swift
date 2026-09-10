import Foundation
import NavidromeClient

extension Player {
    /// The remaining overlap time, exposed only while both MPV contexts are
    /// audibly playing. The UI observes `currentTime`, which advances during
    /// the transition and naturally refreshes this value.
    var crossfadeRemainingTime: Double? {
        guard isCrossfading, let active = automix.activeCrossfade else { return nil }
        return max(0, active.duration - (currentTime - active.startTime))
    }

    var crossfadeStatusText: String? {
        guard let remaining = crossfadeRemainingTime else { return nil }
        return L10n.format("format.crossfade.remaining", Int(ceil(remaining)))
    }

    /// Starts and advances an ordinary crossfade only after the successor has
    /// been fully prepared. The active MPV context remains the timeline source,
    /// so the operation never adds a timer to the audio callback path.
    func evaluateAutomixCrossfade(at seconds: Double) {
        guard engineKind == .mpv,
              automix.enabled,
              isPlaying,
              !isScrubbing,
              trackDuration > 0 else {
            return
        }
        if let active = automix.activeCrossfade {
            advanceAutomixCrossfade(active, at: seconds)
            return
        }
        guard let successor = nextSongForPreloading,
              automix.preloadedNextSongID == successor.id,
              automix.preloadedMPVEngine.isLoaded else {
            return
        }
        let plan = automix.transitionPlan ?? AutomixCrossfade.fallbackPlan(
            currentDuration: trackDuration,
            preferredFadeDuration: automix.fadeDuration
        )
        guard seconds >= plan.fadeOutStart else { return }

        automix.preloadedMPVEngine.volume = 0
        automix.preloadedMPVEngine.play()
        let active = ActiveAutomixCrossfade(
            successorID: successor.id,
            startTime: plan.fadeOutStart,
            duration: max(0.1, plan.fadeDuration)
        )
        automix.activeCrossfade = active
        isCrossfading = true
        updateNowPlayingInfo()
        advanceAutomixCrossfade(active, at: seconds)
    }

    /// Restores the outgoing track to the user's volume and silences the
    /// prepared successor. Call this before a seek, queue mutation or setting
    /// change invalidates the prepared transition.
    func cancelAutomixCrossfade() {
        guard automix.activeCrossfade != nil else {
            isCrossfading = false
            return
        }
        automix.activeCrossfade = nil
        isCrossfading = false
        mpvEngine.volume = outputGain
        automix.preloadedMPVEngine.pause()
        automix.preloadedMPVEngine.volume = 0
        updateNowPlayingInfo()
    }

    private func advanceAutomixCrossfade(
        _ active: ActiveAutomixCrossfade,
        at seconds: Double
    ) {
        guard automix.preloadedNextSongID == active.successorID,
              automix.preloadedMPVEngine.isLoaded else {
            cancelAutomixCrossfade()
            return
        }
        let progress = (seconds - active.startTime) / active.duration
        let gains = AutomixCrossfade.gains(progress: progress)
        mpvEngine.volume = outputGain * gains.outgoing
        automix.preloadedMPVEngine.volume = outputGain * gains.incoming
    }

    func handleMPVTrackEnded() {
        if let active = automix.activeCrossfade {
            completeAutomixCrossfade(active)
            return
        }
        onTrackEnded?()
    }

    private func completeAutomixCrossfade(_ active: ActiveAutomixCrossfade) {
        guard let outgoing = currentSong,
              let nextIndex = nextQueueIndexForPreloading,
              queue.indices.contains(nextIndex),
              queue[nextIndex].id == active.successorID else {
            cancelAutomixCrossfade()
            return
        }
        automix.activeCrossfade = nil
        mpvEngine.stop()
        currentIndex = nextIndex
        isCrossfading = false
        startCurrent()
        onTrackCrossfaded?(outgoing)
    }
}
