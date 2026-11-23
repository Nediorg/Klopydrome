import Foundation
import NavidromeClient

extension AppState {
    func resolveSongs(for payload: TrackDragPayload) async -> [SubsonicSong] {
        switch payload.kind {
        case .songs(let ids):
            return await resolveSongsWithFallback(byIDs: ids)
        case .album(let albumID):
            if let cached = library.albumDetails[albumID]?.song, !cached.isEmpty {
                return cached
            }
            let dummyAlbum = SubsonicAlbum(id: albumID, title: "", artist: nil)
            return await albumSongs(dummyAlbum)
        case .queueItem(let index, let songID):
            if index >= 0 && index < player.queue.count {
                let candidate = player.queue[index]
                if candidate.id == songID {
                    return [candidate]
                }
            }
            return await resolveSongsWithFallback(byIDs: [songID])
        case .playlistTrack(let playlistID, let index, let songID):
            if let songs = playlistLoadStates[playlistID]?.songs, index >= 0 && index < songs.count {
                let candidate = songs[index]
                if candidate.id == songID {
                    return [candidate]
                }
            }
            return await resolveSongsWithFallback(byIDs: [songID])
        }
    }

    func resolveSongs(byIDs ids: [String]) -> [SubsonicSong] {
        let idSet = Set(ids)
        var songMap: [String: SubsonicSong] = [:]

        func indexSongs(_ candidates: [SubsonicSong]) {
            for song in candidates where idSet.contains(song.id) && songMap[song.id] == nil {
                songMap[song.id] = song
            }
        }

        indexSongs(player.queue)
        indexSongs(player.history)
        indexSongs(downloadedSongs)
        indexSongs(library.favoritesSongs)
        indexSongs(library.songs)
        for state in playlistLoadStates.values {
            indexSongs(state.songs)
        }
        for detail in library.albumDetails.values {
            if let songs = detail.song {
                indexSongs(songs)
            }
        }

        return ids.compactMap { songMap[$0] }
    }

    private func resolveSongsWithFallback(byIDs ids: [String]) async -> [SubsonicSong] {
        let local = resolveSongs(byIDs: ids)
        if local.count == ids.count || !allowsNetworkRequests {
            return local
        }
        guard let client else { return local }
        var byID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let missingIDs = ids.filter { byID[$0] == nil }
        for id in missingIDs {
            if let fetched = try? await client.getSong(id: id) {
                byID[id] = fetched
            }
        }
        return ids.compactMap { byID[$0] }
    }
}
