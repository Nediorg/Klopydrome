import Foundation
import NavidromeClient

extension Player {
    func configureCrossfade(enabled: Bool, fadeDuration: Double, applyToAlbums: Bool) {
        crossfadeEnabled = enabled
        crossfadeDuration = CrossfadeMath.clampDuration(fadeDuration)
        crossfadeApplyToAlbums = applyToAlbums
        if !enabled {
            cancelCrossfade()
        } else if let next = nextSongForPreloading, shouldCrossfade(to: next) {
            resetPreloadedNext()
        }
    }

    func shouldCrossfade(to next: SubsonicSong) -> Bool {
        guard crossfadeEnabled, engineKind == .mpv, repeatMode != .one else { return false }
        if let nextDuration = next.duration, nextDuration > 0, Double(nextDuration) <= crossfadeDuration + 2 {
            return false
        }
        return crossfadeApplyToAlbums || !Self.isSameAlbum(currentSong, next)
    }

    static func isSameAlbum(_ lhs: SubsonicSong?, _ rhs: SubsonicSong?) -> Bool {
        guard let lhs, let rhs else { return false }
        if let lhsID = lhs.albumId, !lhsID.isEmpty,
           let rhsID = rhs.albumId, !rhsID.isEmpty {
            return lhsID == rhsID
        }
        if let lhsParent = lhs.parent, !lhsParent.isEmpty,
           let rhsParent = rhs.parent, !rhsParent.isEmpty {
            return lhsParent == rhsParent
        }
        if let lhsAlbum = lhs.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let rhsAlbum = rhs.album?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !lhsAlbum.isEmpty, lhsAlbum == rhsAlbum {
            let lhsArtist = (lhs.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rhsArtist = (rhs.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lhsArtist == rhsArtist
        }
        return false
    }

    func evaluateCrossfade(at currentTime: Double) {
        guard !isCrossfading, engineKind == .mpv, isPlaying, !isScrubbing, !isSeekInFlight,
              trackDuration > crossfadeDuration + 2,
              let next = nextSongForPreloading,
              shouldCrossfade(to: next) else {
            return
        }
        let remaining = trackDuration - currentTime
        let prepareLead = max(crossfadeDuration + 8, 12)
        if remaining <= prepareLead {
            prepareCrossfadeEngine(for: next)
        }
        if remaining <= crossfadeDuration,
           let engine = crossfadeEngine,
           crossfadeNextSongID == next.id,
           engine.isLoaded {
            startCrossfade(to: next)
        }
    }

    func applyMPVVolumes() {
        guard isCrossfading, let active = activeCrossfade else {
            mpvEngine.volume = outputGain
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - active.startTime
        let gains = CrossfadeMath.gains(progress: elapsed / max(0.1, active.duration))
        mpvEngine.volume = outputGain * gains.outgoing
        crossfadeEngine?.volume = outputGain * gains.incoming
    }

    func resetCrossfadePreload() {
        if let engine = crossfadeEngine {
            clearCallbacks(on: engine)
            engine.stop()
            engine.destroyAsync()
            crossfadeEngine = nil
        }
        crossfadeNextSongID = nil
        crossfadeSourceURL = nil
    }

    func cancelCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        resetCrossfadePreload()
        isCrossfading = false
        activeCrossfade = nil
        crossfadeStepProgress = 0
        mpvEngine.volume = outputGain
    }

    func completeCrossfade() {
        guard isCrossfading, let incoming = crossfadeEngine, let active = activeCrossfade else {
            cancelCrossfade()
            return
        }
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        let endedSong = currentSong
        let retiring = mpvEngine
        clearCallbacks(on: retiring)
        retiring.stop()
        retiring.destroyAsync()

        mpvEngine = incoming
        crossfadeEngine = nil
        mpvEngine.volume = outputGain
        setUpMPVEngine()

        if let expected = nextQueueIndexForPreloading,
           queue.indices.contains(expected),
           queue[expected].id == active.successorID {
            currentIndex = expected
        } else if let nextIndex = queue.firstIndex(where: { $0.id == active.successorID }) {
            currentIndex = nextIndex
        }
        currentSourceURL = crossfadeSourceURL
        crossfadeSourceURL = nil
        crossfadeNextSongID = nil
        mpvLoadGeneration += 1
        mpvStreamOffset = 0
        resetSeekState()
        isLoading = false
        isBuffering = incoming.isBuffering
        currentTime = incoming.currentTimeValue
        duration = 0
        syncDurationFromMPVEngine()
        isCrossfading = false
        activeCrossfade = nil
        crossfadeStepProgress = 0
        if let song = currentSong {
            history.append(song)
            if history.count > 500 { history.removeFirst(history.count - 500) }
        }
        if let endedSong { onTrackCrossfaded?(endedSong) }
        updateNowPlayingInfo()
    }

    func pauseCrossfade() {
        guard isCrossfading, activeCrossfade?.pausedAt == nil else { return }
        activeCrossfade?.pausedAt = CFAbsoluteTimeGetCurrent()
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
    }

    func resumeCrossfade() {
        guard isCrossfading, let pausedAt = activeCrossfade?.pausedAt else { return }
        let pausedDuration = max(0, CFAbsoluteTimeGetCurrent() - pausedAt)
        activeCrossfade?.startTime += pausedDuration
        activeCrossfade?.pausedAt = nil
        scheduleCrossfadeTimer()
    }

    private func prepareCrossfadeEngine(for song: SubsonicSong) {
        guard crossfadeNextSongID != song.id,
              let url = onNextTrackPreloadRequest?(song) else {
            return
        }
        resetCrossfadePreload()
        let engine = MPVPlaybackEngine()
        engine.replayGainMode = replayGainMode
        engine.replayGainPreampDB = replayGainPreampDB
        engine.silenceTrimMode = silenceTrimMode
        engine.volume = 0
        engine.onFailure = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isCrossfading {
                    self.cancelCrossfade()
                } else {
                    self.resetCrossfadePreload()
                }
            }
        }
        crossfadeEngine = engine
        crossfadeNextSongID = song.id
        crossfadeSourceURL = url
        Task { try? await engine.load(url: url, streamRecordURL: nil) }
    }

    private func startCrossfade(to next: SubsonicSong) {
        guard let incoming = crossfadeEngine, incoming.isLoaded else { return }
        resetPreloadedNext()
        incoming.volume = 0
        incoming.play()
        activeCrossfade = ActiveCrossfade(
            successorID: next.id,
            startTime: CFAbsoluteTimeGetCurrent(),
            duration: crossfadeDuration
        )
        isCrossfading = true
        crossfadeStepProgress = CrossfadeMath.stepProgress(elapsed: 0, duration: crossfadeDuration)
        updateNowPlayingInfo()
        scheduleCrossfadeTimer()
    }

    private func scheduleCrossfadeTimer() {
        crossfadeTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickCrossfade()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer
    }

    private func tickCrossfade() {
        guard isCrossfading, isPlaying, let active = activeCrossfade, active.pausedAt == nil else { return }
        if crossfadeEngine?.isEnded == true {
            if crossfadeEngine?.isLoaded == true {
                completeCrossfade()
            } else {
                cancelCrossfade()
            }
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - active.startTime
        let progress = elapsed / max(0.1, active.duration)
        let gains = CrossfadeMath.gains(progress: progress)
        mpvEngine.volume = outputGain * gains.outgoing
        crossfadeEngine?.volume = outputGain * gains.incoming
        let step = CrossfadeMath.stepProgress(elapsed: elapsed, duration: active.duration)
        if crossfadeStepProgress != step {
            crossfadeStepProgress = step
        }
        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    private func clearCallbacks(on engine: MPVPlaybackEngine) {
        engine.onTrackEnded = nil
        engine.onFailure = nil
        engine.onFailureCode = nil
        engine.onTimeUpdate = nil
        engine.onDurationUpdate = nil
        engine.onBufferingUpdate = nil
        engine.onFileLoaded = nil
        engine.onSeekableUpdate = nil
        engine.onStreamRecordFinished = nil
    }
}
