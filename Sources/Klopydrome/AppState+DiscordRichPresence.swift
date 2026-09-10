import Foundation
import NavidromeClient

extension AppState {
    func refreshDiscordRichPresence() {
        if isDiscordSnoozed {
            discordRichPresence.clear()
            discordConnectionStatus = .idle
            return
        }
        let song = player.currentSong
        let albumID = song?.albumId
        let artworkURL = albumID.flatMap { discordAlbumArtworkURLs[$0] }
        discordRichPresence.update(
            DiscordRichPresenceRequest(
                enabled: serverConfig.effectiveDiscordRichPresenceEnabled,
                applicationID: serverConfig.discordApplicationID,
                showPaused: serverConfig.effectiveDiscordShowPaused,
                artworkURL: artworkURL,
                song: song,
                isPlaying: player.isPlaying,
                currentTime: player.currentTime,
                duration: player.trackDuration
            )
        )
        fetchDiscordArtworkIfNeeded(for: song, albumID: albumID)
    }

    private func fetchDiscordArtworkIfNeeded(for song: SubsonicSong?, albumID: String?) {
        guard !isDiscordSnoozed,
              serverConfig.effectiveDiscordRichPresenceEnabled,
              let client,
              let albumID,
              discordAlbumArtworkURLs[albumID] == nil,
              !discordArtworkUnavailableAlbumIDs.contains(albumID),
              !discordArtworkLoadingAlbumIDs.contains(albumID) else {
            return
        }
        discordArtworkLoadingAlbumIDs.insert(albumID)
        Task { [weak self] in
            let info = try? await client.getAlbumInfo2(id: albumID)
            let rawURL = info?.largeImageUrl ?? info?.mediumImageUrl ?? info?.smallImageUrl
            let artworkURL = DiscordRichPresenceActivity.externalArtworkURL(rawURL)
            guard let self else { return }
            self.discordArtworkLoadingAlbumIDs.remove(albumID)
            if let artworkURL {
                self.discordAlbumArtworkURLs[albumID] = artworkURL
            } else {
                self.discordArtworkUnavailableAlbumIDs.insert(albumID)
            }
            guard self.player.currentSong?.id == song?.id else { return }
            self.refreshDiscordRichPresence()
        }
    }
}
