import Foundation
import NavidromeClient

// MARK: - Stars & ratings

extension AppState {
    func toggleStar<T: Starable>(_ item: T, skipOfflineConfirm: Bool = false) {
        if !skipOfflineConfirm, !confirmOfflineAction() { return }
        let willStar = !isStarred(item)
        withMutation(keyPath: \.starOverrides) { starOverrides[item.id] = willStar }
        if willStar {
            autoCacheStarredItemIfNeeded(item)
        }
        guard let client, !isOfflineSession else {
            queueOfflineStar(id: item.id, kind: item.starKind, isStarred: willStar)
            return
        }
        pushStarToServer(client: client, id: item.id, kind: item.starKind, willStar: willStar)
    }

    /// Effective starred state: any local override wins over the snapshot.
    func isStarred<T: Starable>(_ item: T) -> Bool {
        access(keyPath: \.starOverrides)
        return starOverrides[item.id] ?? (item.starred?.isEmpty == false)
    }

    /// Effective rating (0–5) for display: the last locally-set value wins.
    func effectiveRating(for song: SubsonicSong) -> Int {
        access(keyPath: \.ratingOverrides)
        return ratingOverrides[song.id] ?? song.userRating ?? 0
    }

    /// Sets a 1–5 star rating (0 clears it), optimistic + server sync.
    /// The override is written BEFORE the client guard, so rating works
    /// offline (the push is skipped without a connection and the value
    /// stays until the next full refetch).
    func setRating(_ rating: Int, for song: SubsonicSong, skipOfflineConfirm: Bool = false) {
        if !skipOfflineConfirm, !confirmOfflineAction() { return }
        let clamped = min(max(rating, 0), 5)
        withMutation(keyPath: \.ratingOverrides) { ratingOverrides[song.id] = clamped }
        guard let client, !isOfflineSession else {
            queueOfflineRating(songID: song.id, rating: clamped)
            return
        }
        pushRatingToServer(client: client, id: song.id, rating: clamped)
    }
}
