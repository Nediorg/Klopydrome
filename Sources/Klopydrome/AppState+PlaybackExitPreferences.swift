import Foundation

extension AppState {
    /// Restores app-wide playback choices without touching the server profile.
    /// Called during app-state construction, before a queue can initialize MPV.
    func restorePlaybackExitPreferences() {
        let preferences = PlaybackExitPreferences.load()
        player.volume = preferences.volume
        player.setShuffleEnabled(preferences.shuffleEnabled)
    }

    /// Writes a single snapshot during normal app termination. In particular,
    /// slider drags never cause a UserDefaults or ServerConfig write.
    func savePlaybackExitPreferences() {
        PlaybackExitPreferences(
            volume: player.volume,
            shuffleEnabled: player.shufflePreferenceEnabled
        ).save()
    }
}
