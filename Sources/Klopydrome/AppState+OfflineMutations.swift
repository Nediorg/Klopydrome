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

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Сервер офлайн".localized
        // swiftlint:disable:next line_length
        alert.informativeText = "Клиент находится в офлайн-режиме. После переподключения некоторые изменения могут быть не применены. Всё равно продолжить?".localized
        alert.addButton(withTitle: "Продолжить".localized)
        let cancel = alert.addButton(withTitle: "Отмена".localized)
        cancel.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Не спрашивать снова".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.suppressOfflineActionWarning = true
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
                    starOverrides[id] = star.isStarred
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

    /// Replays queued offline mutations to the server upon reconnection.
    func flushOfflineMutations() async {
        guard let client, let store = ensureOfflineMutationStore() else { return }
        let mutations = await store.currentMutations()
        guard !mutations.stars.isEmpty || !mutations.ratings.isEmpty else { return }

        isFlushingOfflineMutations = true
        defer { isFlushingOfflineMutations = false }

        if !mutations.stars.isEmpty {
            await flushQueuedStars(client: client, store: store, stars: mutations.stars)
        }
        if !mutations.ratings.isEmpty {
            await flushQueuedRatings(client: client, store: store, ratings: mutations.ratings)
        }
        try? await Task.sleep(for: .milliseconds(300))
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
        }
    }

    private nonisolated static let offlineMutationLog = Logger(
        subsystem: "app.klopydrome",
        category: "offline-mutations"
    )
}
