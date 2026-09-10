import Foundation
import NavidromeClient

extension Player {
    var currentSong: SubsonicSong? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// Song presented by Now Playing surfaces. During an active overlap, the
    /// incoming song is already the listener's destination and is shown first.
    var displaySong: SubsonicSong? {
        guard isCrossfading,
              let successorID = automix.activeCrossfade?.successorID,
              let successor = queue.first(where: { $0.id == successorID }) else {
            return currentSong
        }
        return successor
    }

    var hasQueue: Bool { !queue.isEmpty }
}
