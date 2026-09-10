import Foundation
import MediaPlayer

// MARK: Now Playing info / media remote

extension Player {
    /// Publishes the current track and elapsed time to the system media
    /// remote (Control Center, lock screen) and refreshes the Discord
    /// presence. Called on every meaningful transport transition.
    func updateNowPlayingInfo() {
        onDiscordPresenceUpdate?()
        guard let song = displaySong else {
            nowPlayingArtworkTask?.cancel()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayTitle,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyPlaybackDuration: trackDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let album = song.album { info[MPMediaItemPropertyAlbumTitle] = album }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        nowPlayingArtworkTask?.cancel()
        guard let coverArt = song.coverArt, !coverArt.isEmpty else { return }
        let songID = song.id
        nowPlayingArtworkTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await CoverArtStore.shared.image(coverArt: coverArt, size: 600)
            guard !Task.isCancelled,
                  self.displaySong?.id == songID,
                  self.displaySong?.coverArt == coverArt,
                  let image = loaded.image,
                  var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
                return
            }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            updatedInfo[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
        }
    }

    /// Pushes the elapsed-seconds field of the media-remote Now Playing panel,
    /// throttled to a new integer second (shared by both engines).
    @inline(__always)
    func reportNowPlayingSecond(_ seconds: Double) {
        let second = Int(seconds)
        guard second != lastInfoSecond else { return }
        lastInfoSecond = second
        if let info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            var updated = info
            updated[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        } else if displaySong != nil {
            // The system can clear the dictionary while the app is inactive.
            // Rebuild it on the next clock tick instead of losing media keys
            // until another explicit playback action occurs.
            updateNowPlayingInfo()
        }
        // Discord can restart independently. Refresh periodically so an active
        // presence reconnects without waiting for the next playback action.
        if isPlaying, second > 0, second.isMultiple(of: 15) {
            onDiscordPresenceUpdate?()
        }
    }
}
