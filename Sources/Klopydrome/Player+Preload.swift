import Foundation
import NavidromeClient

extension Player {
    /// Starts loading the following MPV track this many seconds before the
    /// current track ends. The prepared engine remains paused and silent; a
    /// later automix phase will promote it into a fade-in source.
    static let nextTrackPreloadWindow: Double = 30

    /// Updates the independent next-track preload preference. Disabling it
    /// releases any prepared source immediately without changing crossfade.
    func configureNextTrackPreloading(enabled: Bool) {
        nextTrackPreloadingEnabled = enabled
        if !enabled { resetPreloadedNext() }
    }

    /// Wires the isolated, muted MPV context used exclusively for next-track
    /// preparation. It must never report transport events into the main player.
    func setUpMPVPreloader() {
        automix.preloadedMPVEngine.volume = 0
        automix.preloadedMPVEngine.onFailure = { [weak self] _ in
            Task { @MainActor in self?.resetPreloadedNext() }
        }
    }

    /// Evaluates whether the queue successor should be opened in the prepared
    /// MPV context. Called from the main MPV clock, so all queue state is read
    /// consistently on the main actor.
    func evaluateNextTrackPreload(at seconds: Double) {
        guard nextTrackPreloadingEnabled,
              engineKind == .mpv, isPlaying, !isScrubbing,
              trackDuration > 0,
              trackDuration - seconds <= Self.nextTrackPreloadWindow,
              let song = nextSongForPreloading else {
            return
        }
        preloadNextMPVTrack(song)
    }

    /// Releases the prepared context whenever it no longer matches the queue.
    /// This is intentionally idempotent: queue edits, manual navigation, and
    /// end-of-track processing can all invalidate preparation safely.
    func resetPreloadedNext() {
        cancelAutomixCrossfade()
        automix.preloadTask?.cancel()
        automix.preloadTask = nil
        automix.transitionAnalysisTask?.cancel()
        automix.transitionAnalysisTask = nil
        automix.transitionPlan = nil
        automix.preloadedMPVEngine.stop()
        automix.preloadedNextSong = nil
        automix.preloadedNextSongID = nil
        automix.preloadedSourceURL = nil
        automix.isPreloadingNext = false
    }

    /// The queue successor after applying the same repeat semantics as `next()`.
    /// Repeating a single item intentionally has no preload target.
    var nextQueueIndexForPreloading: Int? {
        guard queue.count > 1, queue.indices.contains(currentIndex),
              repeatMode != .one else { return nil }
        if currentIndex + 1 < queue.count { return currentIndex + 1 }
        return repeatMode == .all ? queue.startIndex : nil
    }
    var nextSongForPreloading: SubsonicSong? {
        guard let index = nextQueueIndexForPreloading else { return nil }
        return queue[index]
    }

    /// Promotes the prepared successor without resolving its URL again. This is
    /// the hand-off that eliminates the network gap; fade-in will later ramp
    /// its volume instead of calling `play()` at full volume.
    func promotePreloadedMPVTrack(for song: SubsonicSong, autoPlay: Bool, recordHistory: Bool = true) -> Bool {
        guard engineKind == .mpv,
              automix.preloadedNextSongID == song.id,
              automix.preloadedMPVEngine.isLoaded else {
            return false
        }
        automix.preloadTask?.cancel()
        automix.preloadTask = nil
        automix.transitionAnalysisTask?.cancel()
        automix.transitionAnalysisTask = nil
        automix.transitionPlan = nil
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        mpvEngine.stop()
        mpvEngine = automix.preloadedMPVEngine
        mpvEngine.volume = outputGain
        mpvLoadGeneration += 1
        mpvStreamOffset = 0
        mpvSeekRestartActive = false
        heldSeekTarget = nil
        transcodeRestartResidual = nil
        mpvRestartStepped = false
        automix.currentSourceURL = automix.preloadedSourceURL
        armMPVFailureFallback(for: automix.currentSourceURL)
        automix.preloadedSourceURL = nil
        automix.preloadedMPVEngine = MPVPlaybackEngine()
        automix.preloadedNextSong = nil
        automix.preloadedNextSongID = nil
        automix.isPreloadingNext = false
        setUpMPVEngine()
        setUpMPVPreloader()
        isPlaying = autoPlay
        isLoading = false
        isBuffering = false
        currentTime = 0
        duration = mpvEngine.duration
        pendingSeekTime = nil
        lastError = nil
        hasReportedFailure = false
        if recordHistory {
            history.append(song)
            if history.count > 500 { history.removeFirst(history.count - 500) }
        }
        if autoPlay {
            mpvEngine.play()
        } else {
            mpvEngine.pause()
        }
        updateNowPlayingInfo()
        return true
    }

    private func preloadNextMPVTrack(_ song: SubsonicSong) {
        guard automix.preloadedNextSongID != song.id,
              let url = automix.onNextTrackPreloadRequest?(song) else {
            return
        }
        resetPreloadedNext()
        automix.preloadedNextSong = song
        automix.preloadedNextSongID = song.id
        automix.preloadedSourceURL = url
        automix.isPreloadingNext = true
        let id = song.id
        automix.preloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.automix.preloadedMPVEngine.load(url: url)
                guard !Task.isCancelled, self.automix.preloadedNextSongID == id else { return }
                self.automix.isPreloadingNext = false
                if self.automix.enabled {
                    self.scheduleTransitionAnalysis()
                }
            } catch {
                guard self.automix.preloadedNextSongID == id else { return }
                self.resetPreloadedNext()
            }
        }
    }
}
