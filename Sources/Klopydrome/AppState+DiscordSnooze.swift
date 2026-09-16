import Foundation

extension AppState {
    private static let discordSnoozeKey = "discordSnoozeUntil"

    /// When non-nil and in the future, Rich Presence is suppressed.
    /// `distantFuture` means snoozed forever until manually resumed.
    var discordSnoozeUntil: Date? {
        get {
            access(keyPath: \.discordSnoozeUntil)
            guard let raw = UserDefaults.standard.object(forKey: Self.discordSnoozeKey) as? Date else { return nil }
            if raw != .distantFuture, raw <= Date() {
                UserDefaults.standard.removeObject(forKey: Self.discordSnoozeKey)
                return nil
            }
            return raw
        }
        set {
            withMutation(keyPath: \.discordSnoozeUntil) {
                if let date = newValue {
                    UserDefaults.standard.set(date, forKey: Self.discordSnoozeKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.discordSnoozeKey)
                }
            }
        }
    }

    var isDiscordSnoozed: Bool {
        if let snoozeSongID = discordSnoozeSongID {
            if player.currentSong?.id == snoozeSongID {
                return true
            }
        }
        access(keyPath: \.discordSnoozeUntil)
        guard let until = UserDefaults.standard.object(forKey: Self.discordSnoozeKey) as? Date else { return false }
        if until == .distantFuture { return true }
        if until > Date() { return true }
        UserDefaults.standard.removeObject(forKey: Self.discordSnoozeKey)
        return false
    }

    func snoozeDiscord(for interval: TimeInterval?) {
        discordSnoozeSongID = nil
        if let interval {
            discordSnoozeUntil = Date().addingTimeInterval(interval)
        } else {
            discordSnoozeUntil = .distantFuture
        }
        discordRichPresence.clear()
        discordConnectionStatus = .idle
    }

    func snoozeDiscordForCurrentTrack() {
        guard let songID = player.currentSong?.id else { return }
        discordSnoozeUntil = nil
        discordSnoozeSongID = songID
        discordRichPresence.clear()
        discordConnectionStatus = .idle
    }

    func resumeDiscordSnooze() {
        discordSnoozeUntil = nil
        discordSnoozeSongID = nil
        refreshDiscordRichPresence()
    }
}
