import Foundation
import NavidromeClient

extension Player {
    static let nextTrackPreloadWindow: Double = 30

    func configureNextTrackPreloading(enabled: Bool) {
        nextTrackPreloadingEnabled = enabled
        if !enabled { resetPreloadedNext() }
    }

    @discardableResult
    func preparePreloadedMPVEngine() -> MPVPlaybackEngine {
        if let existing = automix.preloadedMPVEngine {
            return existing
        }
        let engine = MPVPlaybackEngine()
        engine.volume = 0
        engine.replayGainMode = automix.replayGainMode
        engine.replayGainPreampDB = automix.replayGainPreampDB
        engine.silenceTrimMode = automix.silenceTrimMode
        engine.onFailure = { [weak self] _ in
            Task { @MainActor in self?.resetPreloadedNext() }
        }
        automix.preloadedMPVEngine = engine
        return engine
    }

    func setUpMPVPreloader() {
        _ = preparePreloadedMPVEngine()
    }

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

    func resetPreloadedNext() {
        cancelAutomixCrossfade()
        automix.preloadTask?.cancel()
        automix.preloadTask = nil
        automix.transitionAnalysisTask?.cancel()
        automix.transitionAnalysisTask = nil
        automix.transitionPlan = nil
        automix.preloadedMPVEngine?.stop()
        automix.preloadedMPVEngine = nil
        automix.preloadedNextSong = nil
        automix.preloadedNextSongID = nil
        automix.preloadedSourceURL = nil
        automix.isPreloadingNext = false
    }

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

    func promotePreloadedMPVTrack(for song: SubsonicSong, autoPlay: Bool, recordHistory: Bool = true) -> Bool {
        guard engineKind == .mpv,
              automix.preloadedNextSongID == song.id,
              let preloaded = automix.preloadedMPVEngine,
              preloaded.isLoaded else {
            return false
        }
        cancelAutomixCrossfade()
        automix.preloadTask?.cancel()
        automix.preloadTask = nil
        automix.transitionAnalysisTask?.cancel()
        automix.transitionAnalysisTask = nil
        automix.transitionPlan = nil
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        mpvEngine.stop()
        mpvEngine = preloaded
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
        automix.preloadedMPVEngine = nil
        automix.preloadedNextSong = nil
        automix.preloadedNextSongID = nil
        automix.isPreloadingNext = false
        setUpMPVEngine()
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
        let engine = preparePreloadedMPVEngine()
        if let coverArt = song.coverArt, !coverArt.isEmpty {
            Task {
                _ = await CoverArtStore.shared.image(coverArt: coverArt, size: 240)
            }
        }
        automix.preloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await engine.load(url: url)
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
