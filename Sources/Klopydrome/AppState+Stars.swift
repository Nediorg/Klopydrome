import Foundation
import NavidromeClient

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

    func isStarred<T: Starable>(_ item: T) -> Bool {
        access(keyPath: \.starOverrides)
        return starOverrides[item.id] ?? (item.starred?.isEmpty == false)
    }

    func effectiveRating(for song: SubsonicSong) -> Int {
        access(keyPath: \.ratingOverrides)
        return ratingOverrides[song.id] ?? song.userRating ?? 0
    }

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
