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
        if !automix.applyToAlbums,
           let current = currentSong,
           let successor = nextSongForPreloading,
           Player.isIntraAlbumTransition(outgoing: current, incoming: successor, isShuffled: shuffle) {
            if automix.activeCrossfade != nil {
                cancelAutomixCrossfade()
            }
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
        let expected = trackDuration
        if expected > 0, currentTime + 3 < expected {
            if currentSourceIsRemoteTranscode {
                performTranscodeRestart(at: currentTime)
                return
            }
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

    // MARK: - Album Detection

    /// Determines whether two tracks belong to the same album.
    /// Prefers matching unified ID (`albumId` or `parent`), falling back to matching
    /// album title and compatible artist metadata.
    static func isSameAlbum(_ first: SubsonicSong, _ second: SubsonicSong) -> Bool {
        let firstID = (first.albumId?.isEmpty == false ? first.albumId : nil) ?? first.parent
        let secondID = (second.albumId?.isEmpty == false ? second.albumId : nil) ?? second.parent
        if let firstID, !firstID.isEmpty, let secondID, !secondID.isEmpty, firstID == secondID {
            return true
        }

        let firstAlbum = first.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondAlbum = second.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstAlbum, !firstAlbum.isEmpty,
              let secondAlbum, !secondAlbum.isEmpty,
              firstAlbum.caseInsensitiveCompare(secondAlbum) == .orderedSame else {
            return false
        }

        return isCompatibleAlbumArtist(first, second)
    }

    private static func isCompatibleAlbumArtist(_ first: SubsonicSong, _ second: SubsonicSong) -> Bool {
        let firstAlbumArtistId = first.albumArtistId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondAlbumArtistId = second.albumArtistId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstAlbumArtistId, !firstAlbumArtistId.isEmpty,
           let secondAlbumArtistId, !secondAlbumArtistId.isEmpty,
           firstAlbumArtistId == secondAlbumArtistId {
            return true
        }

        let firstArtistId = first.artistId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondArtistId = second.artistId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstArtistId, !firstArtistId.isEmpty,
           let secondArtistId, !secondArtistId.isEmpty,
           firstArtistId == secondArtistId {
            return true
        }

        if first.isVariousArtists || second.isVariousArtists {
            return true
        }

        let firstAlbumArtist = first.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondAlbumArtist = second.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstAlbumArtist, !firstAlbumArtist.isEmpty,
           let secondAlbumArtist, !secondAlbumArtist.isEmpty,
           firstAlbumArtist.caseInsensitiveCompare(secondAlbumArtist) == .orderedSame {
            return true
        }

        let firstArtist = (firstAlbumArtist ?? first.artist)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondArtist = (secondAlbumArtist ?? second.artist)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstArtist, !firstArtist.isEmpty,
              let secondArtist, !secondArtist.isEmpty else {
            return true
        }

        if firstArtist.caseInsensitiveCompare(secondArtist) == .orderedSame {
            return true
        }

        let lowerFirst = firstArtist.lowercased()
        let lowerSecond = secondArtist.lowercased()
        return lowerFirst.contains(lowerSecond) || lowerSecond.contains(lowerFirst)
    }

    /// Checks if two tracks form an in-sequence transition within an album
    /// (same disc track N -> N+1).
    static func isConsecutiveAlbumTrack(outgoing: SubsonicSong, incoming: SubsonicSong) -> Bool {
        guard let outTrack = outgoing.track, let inTrack = incoming.track,
              outTrack > 0, inTrack > 0 else {
            return false
        }
        let outDisc = outgoing.discNumber ?? 1
        let inDisc = incoming.discNumber ?? 1
        return inDisc == outDisc && inTrack == outTrack + 1
    }

    /// Determines whether the transition between outgoing and incoming tracks
    /// is an intra-album transition where crossfade should be suppressed.
    static func isIntraAlbumTransition(
        outgoing: SubsonicSong,
        incoming: SubsonicSong,
        isShuffled: Bool = false
    ) -> Bool {
        isSameAlbum(outgoing, incoming)
    }
}
