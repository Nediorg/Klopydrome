import Foundation

extension AppState {
    func restorePlaybackExitPreferences() {
        let preferences = PlaybackExitPreferences.load()
        player.volume = preferences.volume
        player.setShuffleEnabled(preferences.shuffleEnabled)
    }

    func savePlaybackExitPreferences() {
        PlaybackExitPreferences(
            volume: player.volume,
            shuffleEnabled: player.shufflePreferenceEnabled
        ).save()
    }
}
