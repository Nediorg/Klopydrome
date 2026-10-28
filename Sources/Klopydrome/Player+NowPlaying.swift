import Foundation
import MediaPlayer

extension Player {
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
        let side = MiniPlayerPanelController.shared.userCompactSide
        nowPlayingArtworkTask = Task { [weak self] in
            guard let self else { return }
            let loaded = await CoverArtStore.shared.image(coverArt: coverArt, size: 600)
            MiniPlayerVariableBlurCache.shared.prewarmBlur(coverArt: coverArt, size: side)
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
            updateNowPlayingInfo()
        }
        if isPlaying, second > 0, second.isMultiple(of: 15) {
            onDiscordPresenceUpdate?()
        }
    }
}
