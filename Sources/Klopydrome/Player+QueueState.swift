import Foundation
import NavidromeClient

extension Player {
    var currentSong: SubsonicSong? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var displaySong: SubsonicSong? {
        guard isCrossfading,
              let successorID = automix.activeCrossfade?.successorID,
              let successor = queue.first(where: { $0.id == successorID }) else {
            return currentSong
        }
        return successor
    }

    var hasQueue: Bool { !queue.isEmpty }

    func remove(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if queue.count <= 1 {
            setQueue([])
            return
        }
        if index == currentIndex {
            let nextIndex = (currentIndex + 1 < queue.count) ? currentIndex + 1 : 0
            let nextSong = queue[nextIndex]
            queue.remove(at: index)
            if let newIndex = queue.firstIndex(where: { $0.id == nextSong.id }) {
                currentIndex = newIndex
                startCurrent()
            } else {
                currentIndex = min(index, queue.count - 1)
                startCurrent()
            }
        } else {
            queue.remove(at: index)
            if index < currentIndex {
                currentIndex = max(0, currentIndex - 1)
            }
        }
    }

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
