import Foundation
import NavidromeClient

extension Player {
    var shuffleMode: ShuffleMode { shuffleState.mode }

    func toggleShuffle() {
        setShuffleEnabled(!shuffle)
    }

    func setShuffleEnabled(_ enabled: Bool) {
        shufflePreferenceEnabled = enabled
        if enabled {
            turnShuffleOn()
        } else {
            turnShuffleOff()
        }
    }

    func setShuffleMode(_ mode: ShuffleMode) {
        guard shuffleState.mode != mode else { return }
        let wasShuffling = shuffle
        if wasShuffling { turnShuffleOff() }
        shuffleState.mode = mode
        if wasShuffling { turnShuffleOn() }
    }

    private func turnShuffleOn() {
        guard hasQueue, !shuffle else { return }
        resetPreloadedNext()
        shuffleState.originalQueue = queue
        var rest = queue
        if let current = currentSong {
            rest.removeAll { $0.id == current.id }
        }
        let shuffled = shuffled(rest, by: shuffleState.mode)
        shuffleState.shuffledQueue = shuffled
        queue = [currentSong].compactMap { $0 } + shuffled
        currentIndex = 0
        shuffle = true
    }

    private func turnShuffleOff() {
        guard shuffle else { return }
        resetPreloadedNext()
        if let current = currentSong,
           let index = shuffleState.originalQueue.firstIndex(where: { $0.id == current.id }) {
            queue = shuffleState.originalQueue
            currentIndex = index
        } else if !shuffleState.originalQueue.isEmpty {
            queue = shuffleState.originalQueue
            currentIndex = 0
        }
        shuffleState.originalQueue = []
        shuffleState.shuffledQueue = []
        shuffle = false
    }

    private func shuffled(_ songs: [SubsonicSong], by mode: ShuffleMode) -> [SubsonicSong] {
        switch mode {
        case .songs:
            return songs.shuffled()
        case .albums:
            return shuffledBlocks(songs) { song in
                song.albumId ?? ((song.album ?? song.id) + "\\u{0}" + (song.artist ?? ""))
            }
        case .groups:
            return shuffledBlocks(songs) { song in
                song.albumArtist ?? song.artist ?? song.id
            }
        }
    }

    /// Randomizes blocks but preserves the source order inside every block.
    /// Albums are blocks by album id; groups use album artist/artist because
    /// Subsonic does not provide an independent group field on songs.
    private func shuffledBlocks(
        _ songs: [SubsonicSong],
        key: (SubsonicSong) -> String
    ) -> [SubsonicSong] {
        var keys: [String] = []
        var blocks: [String: [SubsonicSong]] = [:]
        for song in songs {
            let value = key(song)
            if blocks[value] == nil { keys.append(value) }
            blocks[value, default: []].append(song)
        }
        return keys.shuffled().flatMap { blocks[$0] ?? [] }
    }
}
