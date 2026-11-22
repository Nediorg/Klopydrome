import Foundation
import NavidromeClient

extension Player {
    func configureNextTrackPreloading(enabled: Bool) {
        nextTrackPreloadingEnabled = enabled
        if !enabled { resetPreloadedNext() }
    }

    func evaluateNextTrackPreload(at seconds: Double) {
        guard nextTrackPreloadingEnabled,
              engineKind == .mpv, isPlaying, !isScrubbing,
              let song = nextSongForPreloading,
              !shouldCrossfade(to: song) else {
            return
        }
        if preloadedNextSongID != song.id || !mpvEngine.hasAppendedTrack {
            preloadNextMPVTrack(song)
        }
    }

    func resetPreloadedNext() {
        mpvEngine.clearAppended()
        preloadedNextSong = nil
        preloadedNextSongID = nil
        preloadedSourceURL = nil
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

    var hasLoadedPreloadForNextTrack: Bool {
        guard engineKind == .mpv,
              repeatMode != .one,
              let next = nextSongForPreloading,
              preloadedNextSongID == next.id else {
            return false
        }
        return mpvEngine.hasAppendedTrack || mpvEngine.didAdvanceToAppendedTrack
    }

    func promotePreloadedMPVTrack(for song: SubsonicSong, autoPlay: Bool, recordHistory: Bool = true) -> Bool {
        guard engineKind == .mpv,
              preloadedNextSongID == song.id,
              mpvEngine.hasAppendedTrack || mpvEngine.didAdvanceToAppendedTrack else {
            return false
        }
        if mpvEngine.didAdvanceToAppendedTrack {
            mpvEngine.pruneFinishedHead()
        } else if mpvEngine.hasAppendedTrack {
            mpvEngine.skipToAppendedTrack(autoPlay: autoPlay)
        }
        applyPromotedTrackState(for: song, autoPlay: autoPlay, recordHistory: recordHistory)
        if nextTrackPreloadingEnabled, let next = nextSongForPreloading {
            preloadNextMPVTrack(next)
        }
        onTrackPromoted?(song)
        return true
    }

    private func applyPromotedTrackState(for song: SubsonicSong, autoPlay: Bool, recordHistory: Bool) {
        currentSourceURL = preloadedSourceURL
        preloadedSourceURL = nil
        preloadedNextSong = nil
        preloadedNextSongID = nil
        mpvLoadGeneration += 1
        mpvStreamOffset = 0
        resetSeekState()
        isLoading = false
        isPlaying = autoPlay
        currentTime = 0
        duration = mpvEngine.duration > 0 ? mpvEngine.duration : Double(song.duration ?? 0)
        lastError = nil
        hasReportedFailure = false
        if recordHistory {
            history.append(song)
            if history.count > 500 { history.removeFirst(history.count - 500) }
        }
        updateNowPlayingInfo()
    }

    func preloadNextMPVTrack(_ song: SubsonicSong) {
        guard preloadedNextSongID != song.id || !mpvEngine.hasAppendedTrack,
              let url = onNextTrackPreloadRequest?(song) else {
            return
        }
        resetPreloadedNext()
        preloadedNextSong = song
        preloadedNextSongID = song.id
        preloadedSourceURL = url
        if let coverArt = song.coverArt, !coverArt.isEmpty {
            Task {
                _ = await CoverArtStore.shared.image(coverArt: coverArt, size: 240)
            }
        }
        mpvEngine.append(url: url)
    }

    func syncPreloadedNextWithQueue() {
        guard engineKind == .mpv, nextTrackPreloadingEnabled else { return }
        let nextID = nextSongForPreloading?.id
        if preloadedNextSongID != nextID {
            resetPreloadedNext()
            if isPlaying, !isScrubbing, let next = nextSongForPreloading {
                preloadNextMPVTrack(next)
            }
        }
    }
}
