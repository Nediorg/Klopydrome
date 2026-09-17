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

    /// Removes a song at the specified queue index, adjusting currentIndex appropriately.
    func remove(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if queue.count == 1 {
            setQueue([])
            return
        }
        if index == currentIndex {
            next()
            let newIndex = index < queue.count ? index : queue.count - 1
            if queue.indices.contains(newIndex) {
                queue.remove(at: newIndex)
                if currentIndex >= queue.count {
                    currentIndex = max(0, queue.count - 1)
                }
            }
        } else {
            queue.remove(at: index)
            if index < currentIndex {
                currentIndex = max(0, currentIndex - 1)
            }
        }
    }

    /// Moves songs within the queue (drag-and-drop support).
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !queue.isEmpty else { return }
        let currentID = currentSong?.id
        var updated = queue
        updated.move(fromOffsets: offsets, toOffset: destination)
        queue = updated
        if let currentID, let newIndex = queue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = newIndex
        }
    }
}
