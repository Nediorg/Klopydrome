import AppKit
import Foundation
import NavidromeClient
import os

extension AppState {
    /// Confirms whether a server-side action should proceed while in offline mode.
    /// Returns `true` if online, if warnings are suppressed, or if the user clicks "Continue".
    @MainActor
    func confirmOfflineAction() -> Bool {
        guard isOfflineSession else { return true }
        guard !serverConfig.effectiveSuppressOfflineActionWarning else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Сервер офлайн".localized
        let msg = "После переподключения некоторые изменения могут быть не применены. Всё равно продолжить?".localized
        alert.informativeText = msg
        alert.addButton(withTitle: "Продолжить".localized)
        let cancel = alert.addButton(withTitle: "Отмена".localized)
        cancel.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.effectiveSuppressOfflineActionWarning = true
            saveSettings()
        }
        return response == .alertFirstButtonReturn
    }

    /// Helper to access or lazily create the offline mutations store.
    func ensureOfflineMutationStore() -> OfflineMutationStore? {
        if let offlineMutationStore { return offlineMutationStore }
        let hostCandidate = URL(string: serverConfig.url)?.host ?? currentOfflineHost
        guard let host = hostCandidate, !host.isEmpty else { return nil }
        let store = OfflineMutationStore(serverHost: host)
        self.offlineMutationStore = store
        return store
    }

    /// Restores any queued offline stars/ratings into in-memory overrides.
    func restorePendingOfflineMutations() async {
        guard let store = ensureOfflineMutationStore() else { return }
        let mutations = await store.currentMutations()
        if !mutations.stars.isEmpty {
            withMutation(keyPath: \.starOverrides) {
                for (id, star) in mutations.stars {
                    if star.kind == .playlist {
                        if star.isStarred {
                            followedPlaylistIDs.insert(id)
                        } else {
                            followedPlaylistIDs.remove(id)
                        }
                    } else {
                        starOverrides[id] = star.isStarred
                    }
                }
            }
        }
        if !mutations.ratings.isEmpty {
            withMutation(keyPath: \.ratingOverrides) {
                for (id, rating) in mutations.ratings {
                    ratingOverrides[id] = rating.rating
                }
            }
        }
    }

    @discardableResult
    func queueOfflineStar(id: String, kind: StarKind, isStarred: Bool) -> Task<Void, Never>? {
        guard let store = ensureOfflineMutationStore() else { return nil }
        return Task {
            await store.recordStar(id: id, kind: kind, isStarred: isStarred)
        }
    }

    func pushStarToServer(client: SubsonicClient, id: String, kind: StarKind, willStar: Bool) {
        guard kind != .playlist else { return }
        let capturedClient = client
        Task(priority: .userInitiated) {
            do {
                switch (kind, willStar) {
                case (.song, true): try await capturedClient.star(songIds: [id])
                case (.song, false): try await capturedClient.unstar(songIds: [id])
                case (.album, true): try await capturedClient.star(albumIds: [id])
                case (.album, false): try await capturedClient.unstar(albumIds: [id])
                case (.artist, true): try await capturedClient.star(artistIds: [id])
                case (.artist, false): try await capturedClient.unstar(artistIds: [id])
                case (.playlist, _): break
                }
            } catch is CancellationError {
                return
            } catch {
                Self.offlineMutationLog.error(
                    "star push failed \(id, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    @discardableResult
    func queueOfflineRating(songID: String, rating: Int) -> Task<Void, Never>? {
        guard let store = ensureOfflineMutationStore() else { return nil }
        return Task {
            await store.recordRating(songID: songID, rating: rating)
        }
    }

    @discardableResult
    func queueOfflineAddToPlaylist(playlistID: String, songIDs: [String]) -> Task<Void, Never>? {
        guard let store = ensureOfflineMutationStore() else { return nil }
        return Task {
            await store.recordPlaylistAdd(playlistID: playlistID, songIDs: songIDs)
        }
    }

    @discardableResult
    func queueOfflineCreatePlaylist(name: String, songIDs: [String], comment: String?) -> Task<Void, Never>? {
        guard let store = ensureOfflineMutationStore() else { return nil }
        return Task {
            await store.recordPlaylistCreate(name: name, songIDs: songIDs, comment: comment)
        }
    }

    func pushRatingToServer(client: SubsonicClient, id: String, rating: Int) {
        let capturedClient = client
        Task(priority: .userInitiated) {
            do {
                try await capturedClient.setRating(rating, id: id)
            } catch is CancellationError {
                return
            } catch {
                Self.offlineMutationLog.error(
                    "rating push failed \(id, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    enum PendingMutationsChoice {
        case apply
        case discard
        case cancel
    }

    enum PendingMutationsContext {
        case previousSession
        case offlineDisabled
    }

    /// Builds a user-friendly list of categories for queued offline actions.
    func pendingActionsSummary(for mutations: OfflineMutations) -> [String] {
        var summary: [String] = []
        if !mutations.playlists.isEmpty {
            summary.append("Изменение или добавление плейлистов".localized)
        }
        if !mutations.stars.isEmpty {
            summary.append("Отметки «Избранное»".localized)
        }
        if !mutations.ratings.isEmpty {
            summary.append("Оценки треков".localized)
        }
        return summary
    }

    /// Displays an NSAlert asking the user whether to apply pending offline mutations.
    @MainActor
    func promptPendingMutationsConfirmation(
        mutations: OfflineMutations,
        context: PendingMutationsContext? = nil
    ) -> PendingMutationsChoice {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Локальные изменения".localized

        let actions = pendingActionsSummary(for: mutations)
        let bulletList = actions.map { "• \($0)" }.joined(separator: "\n")
        let effectiveContext = context ?? (isLaunching ? .previousSession : .offlineDisabled)
        let intro: String
        switch effectiveContext {
        case .previousSession:
            intro = "С прошлого сеанса остались локальные изменения:".localized
        case .offlineDisabled:
            intro = "В офлайн-режиме накопились локальные изменения:".localized
        }
        let question = "Применить их на сервере?".localized
        alert.informativeText = "\(intro)\n\n\(bulletList)\n\n\(question)"

        alert.addButton(withTitle: "Применить".localized)
        alert.addButton(withTitle: "Не применять".localized)
        let cancelButton = alert.addButton(withTitle: "Отмена".localized)
        cancelButton.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.effectiveSuppressOfflinePrompts = true
            saveSettings()
        }

        switch response {
        case .alertFirstButtonReturn:
            return .apply
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    /// Replays queued offline mutations to the server upon reconnection.
    func flushOfflineMutations(
        promptUser: Bool = true,
        context: PendingMutationsContext? = nil
    ) async {
        guard let client, let store = ensureOfflineMutationStore() else { return }
        let mutations = await store.currentMutations()
        guard !mutations.isEmpty else { return }

        if promptUser && !serverConfig.effectiveSuppressOfflinePrompts {
            let choice = promptPendingMutationsConfirmation(mutations: mutations, context: context)
            switch choice {
            case .apply:
                break
            case .discard:
                await store.clear()
                withMutation(keyPath: \.starOverrides) { starOverrides.removeAll() }
                withMutation(keyPath: \.ratingOverrides) { ratingOverrides.removeAll() }
                for (id, star) in mutations.stars where star.kind == .playlist {
                    if star.isStarred {
                        followedPlaylistIDs.remove(id)
                    } else {
                        followedPlaylistIDs.insert(id)
                    }
                }
                return
            case .cancel:
                return
            }
        }

        isFlushingOfflineMutations = true
        defer { isFlushingOfflineMutations = false }

        if !mutations.playlists.isEmpty {
            await flushQueuedPlaylists(client: client, store: store, playlists: mutations.playlists)
        }
        if !mutations.stars.isEmpty {
            await flushQueuedStars(client: client, store: store, stars: mutations.stars)
        }
        if !mutations.ratings.isEmpty {
            await flushQueuedRatings(client: client, store: store, ratings: mutations.ratings)
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func flushQueuedPlaylists(
        client: SubsonicClient,
        store: OfflineMutationStore,
        playlists: [QueuedPlaylistAction]
    ) async {
        var appliedIDs = Set<String>()
        for action in playlists {
            do {
                switch action.type {
                case .addSongs:
                    if let playlistID = action.playlistID {
                        try await client.updatePlaylist(id: playlistID, addSongIds: action.songIDs)
                        appliedIDs.insert(action.id)
                    }
                case .create:
                    if let name = action.playlistName {
                        let created = try await client.createPlaylist(name: name, songIds: action.songIDs)
                        if let comment = action.comment, !comment.isEmpty {
                            try? await client.updatePlaylist(id: created.id, comment: comment)
                        }
                        appliedIDs.insert(action.id)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                let errDesc = String(describing: error)
                Self.offlineMutationLog.error(
                    "flush playlist failed for \(action.id, privacy: .public): \(errDesc, privacy: .public)"
                )
            }
        }
        if !appliedIDs.isEmpty {
            await store.removePlaylists(ids: appliedIDs)
            await refreshPlaylists()
        }
    }

    private func flushQueuedStars(
        client: SubsonicClient,
        store: OfflineMutationStore,
        stars: [String: QueuedStarAction]
    ) async {
        var appliedIDs = Set<String>()
        for (id, star) in stars {
            do {
                try await sendStarRequest(client: client, star: star)
                appliedIDs.insert(id)
            } catch is CancellationError {
                return
            } catch {
                Self.offlineMutationLog.error(
                    "flush star failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        if !appliedIDs.isEmpty {
            await store.removeStars(ids: appliedIDs)
            withMutation(keyPath: \.starOverrides) {
                for id in appliedIDs {
                    if let star = stars[id] {
                        starOverrides[id] = star.isStarred
                    }
                }
            }
        }
    }

    private func sendStarRequest(client: SubsonicClient, star: QueuedStarAction) async throws {
        switch (star.kind, star.isStarred) {
        case (.song, true): try await client.star(songIds: [star.id])
        case (.song, false): try await client.unstar(songIds: [star.id])
        case (.album, true): try await client.star(albumIds: [star.id])
        case (.album, false): try await client.unstar(albumIds: [star.id])
        case (.artist, true): try await client.star(artistIds: [star.id])
        case (.artist, false): try await client.unstar(artistIds: [star.id])
        case (.playlist, _): break
        }
    }

    private func flushQueuedRatings(
        client: SubsonicClient,
        store: OfflineMutationStore,
        ratings: [String: QueuedRatingAction]
    ) async {
        var appliedIDs = Set<String>()
        for (songID, rating) in ratings {
            do {
                try await client.setRating(rating.rating, id: songID)
                appliedIDs.insert(songID)
            } catch is CancellationError {
                return
            } catch {
                let desc = String(describing: error)
                Self.offlineMutationLog.error(
                    "flush rating failed for \(songID, privacy: .public): \(desc, privacy: .public)"
                )
            }
        }
        if !appliedIDs.isEmpty {
            await store.removeRatings(ids: appliedIDs)
            withMutation(keyPath: \.ratingOverrides) {
                for id in appliedIDs {
                    if let rating = ratings[id] {
                        ratingOverrides[id] = rating.rating
                    }
                }
            }
        }
    }

    private nonisolated static let offlineMutationLog = Logger(
        subsystem: "app.klopydrome",
        category: "offline-mutations"
    )
}
