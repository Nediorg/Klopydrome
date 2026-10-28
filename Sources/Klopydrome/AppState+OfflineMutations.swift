import AppKit
import Foundation
import NavidromeClient
import os

extension AppState {
    @MainActor
    func confirmOfflineAction() -> Bool {
        guard isOfflineSession else { return true }
        guard !serverConfig.effectiveSuppressOfflineActionWarning else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Server Offline".localized
        let msg = "After reconnecting, some changes may not be applied. Continue anyway?".localized
        alert.informativeText = msg
        alert.addButton(withTitle: "Continue".localized)
        let cancel = alert.addButton(withTitle: "Cancel".localized)
        cancel.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.effectiveSuppressOfflineActionWarning = true
            saveSettings()
        }
        return response == .alertFirstButtonReturn
    }

    func ensureOfflineMutationStore() -> OfflineMutationStore? {
        if let offlineMutationStore { return offlineMutationStore }
        let hostCandidate = URL(string: serverConfig.url)?.host ?? currentOfflineHost
        guard let host = hostCandidate, !host.isEmpty else { return nil }
        let store = OfflineMutationStore(serverHost: host)
        self.offlineMutationStore = store
        return store
    }

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
                await MainActor.run {
                    _ = self.queueOfflineStar(id: id, kind: kind, isStarred: willStar)
                }
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
    func queueOfflineCreatePlaylist(
        name: String,
        songIDs: [String],
        comment: String?,
        isPublic: Bool = false
    ) -> Task<Void, Never>? {
        guard let store = ensureOfflineMutationStore() else { return nil }
        return Task {
            await store.recordPlaylistCreate(name: name, songIDs: songIDs, comment: comment, isPublic: isPublic)
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
                await MainActor.run {
                    _ = self.queueOfflineRating(songID: id, rating: rating)
                }
            }
        }
    }

    enum PendingMutationsChoice {
        case apply
        case discard
    }

    enum PendingMutationsContext {
        case previousSession
        case offlineDisabled
    }

    func pendingActionsSummary(for mutations: OfflineMutations) -> [String] {
        var summary: [String] = []
        if !mutations.playlists.isEmpty {
            summary.append("Playlist changes or additions".localized)
        }
        if !mutations.stars.isEmpty {
            summary.append("Favorites".localized)
        }
        if !mutations.ratings.isEmpty {
            summary.append("Track ratings".localized)
        }
        return summary
    }

    @MainActor
    func promptPendingMutationsConfirmation(
        mutations: OfflineMutations,
        context: PendingMutationsContext? = nil
    ) -> PendingMutationsChoice {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Local Changes".localized

        let actions = pendingActionsSummary(for: mutations)
        let bulletList = actions.map { "• \($0)" }.joined(separator: "\n")
        let effectiveContext = context ?? (isLaunching ? .previousSession : .offlineDisabled)
        let intro: String
        switch effectiveContext {
        case .previousSession:
            intro = "Local changes from the previous session were not synced:".localized
        case .offlineDisabled:
            intro = "Local changes accumulated while offline:".localized
        }
        let question = "Apply them to the server?".localized
        alert.informativeText = "\(intro)\n\n\(bulletList)\n\n\(question)"

        alert.addButton(withTitle: "Apply".localized)
        let discardButton = alert.addButton(withTitle: "Don't Apply".localized)
        discardButton.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.effectiveSuppressOfflinePrompts = true
            saveSettings()
        }

        switch response {
        case .alertFirstButtonReturn:
            return .apply
        default:
            return .discard
        }
    }

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
                await discardPendingMutations(store: store, mutations: mutations)
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

    private func discardPendingMutations(
        store: OfflineMutationStore,
        mutations: OfflineMutations
    ) async {
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
                        let hasComment = (action.comment != nil && !action.comment!.isEmpty)
                        let isPublic = (action.isPublic == true)
                        if hasComment || isPublic {
                            try? await client.updatePlaylist(
                                id: created.id,
                                comment: action.comment,
                                isPublic: isPublic
                            )
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
