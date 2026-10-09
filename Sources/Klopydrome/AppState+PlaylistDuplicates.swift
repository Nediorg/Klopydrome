import AppKit
import Foundation
import NavidromeClient

/// Pure logic for detecting and resolving duplicate songs when adding to a playlist.
struct PlaylistDuplicateResolver {
    enum ResolutionResult: Equatable {
        case add(songs: [SubsonicSong])
        case needsUserPrompt(duplicates: [SubsonicSong], allTargets: [SubsonicSong])
        case nothingToAdd
    }

    static func resolve(
        targets: [SubsonicSong],
        existingSongs: [SubsonicSong],
        action: DuplicatePlaylistAction
    ) -> ResolutionResult {
        guard !targets.isEmpty else { return .nothingToAdd }
        let existingIDs = Set(existingSongs.map(\.id))
        let duplicates = targets.filter { existingIDs.contains($0.id) }

        guard !duplicates.isEmpty else {
            return .add(songs: targets)
        }

        switch action {
        case .allow:
            return .add(songs: targets)
        case .skip:
            let unique = targets.filter { !existingIDs.contains($0.id) }
            return unique.isEmpty ? .nothingToAdd : .add(songs: unique)
        case .ask:
            return .needsUserPrompt(duplicates: duplicates, allTargets: targets)
        }
    }
}

extension AppState {
    static let duplicatePlaylistActionKey = "duplicatePlaylistAction"

    /// Preference for handling duplicate songs when adding to a playlist.
    var duplicatePlaylistAction: DuplicatePlaylistAction {
        get {
            access(keyPath: \.duplicatePlaylistAction)
            guard let raw = UserDefaults.standard.string(forKey: Self.duplicatePlaylistActionKey),
                  let action = DuplicatePlaylistAction(rawValue: raw) else {
                return .ask
            }
            return action
        }
        set {
            withMutation(keyPath: \.duplicatePlaylistAction) {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.duplicatePlaylistActionKey)
            }
        }
    }

    enum DuplicateUserChoice {
        case addAll
        case addUnique
        case cancel
    }

    /// Adds songs to a playlist, checking for duplicates and prompting the user if needed.
    @MainActor
    func addSongsCheckingDuplicates(_ targets: [SubsonicSong], to playlist: PlaylistSummary) async {
        guard !targets.isEmpty else { return }
        guard confirmOfflineAction() else { return }

        let existing = await playlistSongs(for: playlist)
        let resolution = PlaylistDuplicateResolver.resolve(
            targets: targets,
            existingSongs: existing,
            action: duplicatePlaylistAction
        )

        switch resolution {
        case .add(let songs):
            await addToPlaylist(songs, playlistID: playlist.id)
        case .nothingToAdd:
            break
        case .needsUserPrompt(let duplicates, let allTargets):
            let choice = promptPlaylistDuplicates(duplicates: duplicates, allTargets: allTargets, playlist: playlist)
            switch choice {
            case .addAll:
                await addToPlaylist(allTargets, playlistID: playlist.id)
            case .addUnique:
                let existingIDs = Set(existing.map(\.id))
                let unique = allTargets.filter { !existingIDs.contains($0.id) }
                if !unique.isEmpty {
                    await addToPlaylist(unique, playlistID: playlist.id)
                }
            case .cancel:
                break
            }
        }
    }

    /// Displays a native macOS modal alert when duplicate tracks are detected.
    @MainActor
    private func promptPlaylistDuplicates(
        duplicates: [SubsonicSong],
        allTargets: [SubsonicSong],
        playlist: PlaylistSummary
    ) -> DuplicateUserChoice {
        if allTargets.count == 1 {
            return promptSingleDuplicate(songTitle: allTargets[0].displayTitle, playlist: playlist)
        } else if duplicates.count == allTargets.count {
            return promptAllDuplicates(count: allTargets.count, playlist: playlist)
        } else {
            return promptPartialDuplicates(
                duplicatesCount: duplicates.count,
                totalCount: allTargets.count,
                playlist: playlist
            )
        }
    }

    @MainActor
    private func promptSingleDuplicate(
        songTitle: String,
        playlist: PlaylistSummary
    ) -> DuplicateUserChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized
        alert.messageText = L10n.format("format.playlist.duplicate.singleTitle", songTitle, playlist.displayName)
        alert.informativeText = "Добавить копию трека?".localized
        alert.addButton(withTitle: "Добавить копию".localized)
        let cancelBtn = alert.addButton(withTitle: "Отмена".localized)
        cancelBtn.keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .allow }
            return .addAll
        } else {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .skip }
            return .cancel
        }
    }

    @MainActor
    private func promptAllDuplicates(
        count: Int,
        playlist: PlaylistSummary
    ) -> DuplicateUserChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized
        alert.messageText = L10n.format("format.playlist.duplicate.allTitle", count, playlist.displayName)
        alert.informativeText = "Добавить копии треков?".localized
        alert.addButton(withTitle: "Добавить копии".localized)
        let cancelBtn = alert.addButton(withTitle: "Отмена".localized)
        cancelBtn.keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .allow }
            return .addAll
        } else {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .skip }
            return .cancel
        }
    }

    @MainActor
    private func promptPartialDuplicates(
        duplicatesCount: Int,
        totalCount: Int,
        playlist: PlaylistSummary
    ) -> DuplicateUserChoice {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized
        // swiftlint:disable:next line_length
        alert.messageText = L10n.format("format.playlist.duplicate.multipleTitle", duplicatesCount, totalCount, playlist.displayName)
        alert.informativeText = "Вы можете пропустить существующие песни или добавить копии.".localized
        alert.addButton(withTitle: "Пропустить дубликаты".localized)
        alert.addButton(withTitle: "Добавить все".localized)
        let cancelBtn = alert.addButton(withTitle: "Отмена".localized)
        cancelBtn.keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .skip }
            return .addUnique
        } else if response == .alertSecondButtonReturn {
            if alert.suppressionButton?.state == .on { duplicatePlaylistAction = .allow }
            return .addAll
        } else {
            return .cancel
        }
    }
}
