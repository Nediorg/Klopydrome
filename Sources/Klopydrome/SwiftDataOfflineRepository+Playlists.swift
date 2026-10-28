import Foundation
import SwiftData
import NavidromeClient

extension SwiftDataOfflineRepository {

    public func fetchPlaylistEntries(playlistID: String) throws -> [(trackID: String?, isTrackLinked: Bool)] {
        let desc = FetchDescriptor<OfflinePlaylist>(predicate: #Predicate { $0.id == playlistID })
        guard let playlist = try modelContext.fetch(desc).first else { return [] }
        return playlist.entries.sorted { $0.index < $1.index }.map {
            ($0.trackID, $0.track != nil)
        }
    }

    public func savePlaylists(_ playlists: [PlaylistSummary]) async throws {
        for playlist in playlists {
            let playlistID = playlist.id
            let desc = FetchDescriptor<OfflinePlaylist>(predicate: #Predicate { $0.id == playlistID })
            let model = try modelContext.fetch(desc).first ?? OfflinePlaylist(
                id: playlist.id,
                name: playlist.name ?? "Untitled"
            )
            updatePlaylistMetadata(model, from: playlist)
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    public func savePlaylistDetail(_ detail: PlaylistDetail) async throws {
        let playlistID = detail.id
        let desc = FetchDescriptor<OfflinePlaylist>(predicate: #Predicate { $0.id == playlistID })
        let playlist = try modelContext.fetch(desc).first ?? OfflinePlaylist(
            id: detail.id,
            name: detail.name ?? "Untitled"
        )
        updatePlaylistDetailMetadata(playlist, from: detail)

        for entry in playlist.entries {
            modelContext.delete(entry)
        }
        playlist.entries.removeAll()

        if let songs = detail.entry {
            playlist.tracksSummaryData = try? JSONEncoder().encode(songs)

            let downloadedDesc = FetchDescriptor<OfflineTrack>(
                predicate: #Predicate { $0.isDownloaded }
            )
            let downloadedTracks = try modelContext.fetch(downloadedDesc)
            let downloadedByID = Dictionary(
                downloadedTracks.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            for (index, song) in songs.enumerated() {
                guard let track = downloadedByID[song.id] else { continue }
                let entryID = "\(detail.id)_\(index)"
                let entry = OfflinePlaylistEntry(id: entryID, index: index)
                entry.playlist = playlist
                entry.trackID = song.id
                entry.fallbackTitle = song.title
                entry.fallbackDuration = song.duration
                entry.fallbackArtist = song.artist ?? song.albumArtist
                entry.fallbackAlbum = song.album
                entry.fallbackCoverArt = song.coverArt
                entry.fallbackTrackNumber = song.track
                entry.fallbackDiscNumber = song.discNumber
                entry.fallbackYear = song.year
                entry.fallbackGenre = song.genre
                entry.track = track

                modelContext.insert(entry)
            }
        } else {
            playlist.tracksSummaryData = nil
        }

        modelContext.insert(playlist)
        try modelContext.save()
    }

    public func fetchPlaylistDetail(id: String) async throws -> PlaylistDetail? {
        let desc = FetchDescriptor<OfflinePlaylist>(predicate: #Predicate { $0.id == id })
        guard let playlist = try modelContext.fetch(desc).first else { return nil }

        let songs = try reconstructPlaylistSongs(for: playlist)

        return PlaylistDetail(
            id: playlist.id,
            name: playlist.name,
            comment: playlist.comment,
            owner: playlist.owner,
            coverArt: playlist.coverArt,
            songCount: playlist.songCount ?? songs.count,
            duration: playlist.duration,
            created: playlist.created,
            changed: playlist.changed,
            isPublic: playlist.isPublic,
            entry: songs
        )
    }

    private func reconstructPlaylistSongs(for playlist: OfflinePlaylist) throws -> [SubsonicSong] {
        let downloadedDesc = FetchDescriptor<OfflineTrack>(predicate: #Predicate { $0.isDownloaded })
        let downloadedTracks = try modelContext.fetch(downloadedDesc)
        let downloadedByID = Dictionary(
            downloadedTracks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if let data = playlist.tracksSummaryData,
           let summarySongs = try? JSONDecoder().decode([SubsonicSong].self, from: data) {
            return summarySongs.map { song in
                if let downloaded = downloadedByID[song.id] {
                    return mapTrackToSong(downloaded)
                }
                return song
            }
        }

        let sortedEntries = playlist.entries.sorted { $0.index < $1.index }
        return sortedEntries.map { mapEntryToSong($0, downloadedByID: downloadedByID) }
    }

    private func mapEntryToSong(
        _ entry: OfflinePlaylistEntry,
        downloadedByID: [String: OfflineTrack]
    ) -> SubsonicSong {
        let downloadedTrack: OfflineTrack? = {
            if let track = entry.track, track.isDownloaded {
                return track
            }
            if let trackID = entry.trackID, let downloaded = downloadedByID[trackID] {
                return downloaded
            }
            return nil
        }()

        if let downloadedTrack {
            return mapTrackToSong(downloadedTrack)
        }
        return SubsonicSong(
            id: entry.trackID ?? entry.id,
            title: entry.fallbackTitle ?? "Unknown Track",
            album: entry.fallbackAlbum,
            artist: entry.fallbackArtist,
            track: entry.fallbackTrackNumber,
            year: entry.fallbackYear,
            genre: entry.fallbackGenre,
            coverArt: entry.fallbackCoverArt,
            duration: entry.fallbackDuration,
            discNumber: entry.fallbackDiscNumber
        )
    }

    public func fetchPlaylists() async throws -> [PlaylistSummary] {
        let desc = FetchDescriptor<OfflinePlaylist>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let playlists = try modelContext.fetch(desc)
        return playlists.map { mapPlaylistToSummary($0) }
    }

    public func fetchPlaylists(
        matchingDownloadedTrackIDs downloadedIDs: Set<String>
    ) async throws -> [PlaylistSummary] {
        let desc = FetchDescriptor<OfflinePlaylist>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let playlists = try modelContext.fetch(desc)
        return playlists.compactMap { playlist in
            let hasMatchingTrack: Bool
            if let data = playlist.tracksSummaryData,
               let summarySongs = try? JSONDecoder().decode([SubsonicSong].self, from: data) {
                hasMatchingTrack = summarySongs.contains { downloadedIDs.contains($0.id) }
            } else {
                hasMatchingTrack = playlist.entries.contains { entry in
                    guard let id = entry.trackID ?? entry.track?.id else { return false }
                    return downloadedIDs.contains(id)
                }
            }
            guard hasMatchingTrack else { return nil }
            return mapPlaylistToSummary(playlist)
        }
    }

    private func updatePlaylistMetadata(_ model: OfflinePlaylist, from summary: PlaylistSummary) {
        model.name = summary.name ?? model.name
        model.comment = summary.comment ?? model.comment
        model.owner = summary.owner ?? model.owner
        model.coverArt = summary.coverArt ?? model.coverArt
        model.songCount = summary.songCount ?? model.songCount
        model.duration = summary.duration ?? model.duration
        model.created = summary.created ?? model.created
        model.changed = summary.changed ?? model.changed
        model.isPublic = summary.isPublic ?? model.isPublic
        model.isReadonly = summary.isReadonly ?? model.isReadonly
        model.validUntil = summary.validUntil ?? model.validUntil
        model.updatedAt = Date()
    }

    private func updatePlaylistDetailMetadata(_ model: OfflinePlaylist, from detail: PlaylistDetail) {
        model.name = detail.name ?? model.name
        model.comment = detail.comment ?? model.comment
        model.owner = detail.owner ?? model.owner
        model.coverArt = detail.coverArt ?? model.coverArt
        model.songCount = detail.songCount ?? model.songCount
        model.duration = detail.duration ?? model.duration
        model.created = detail.created ?? model.created
        model.changed = detail.changed ?? model.changed
        model.isPublic = detail.isPublic ?? model.isPublic
        model.updatedAt = Date()
    }

    func mapPlaylistToSummary(_ playlist: OfflinePlaylist) -> PlaylistSummary {
        PlaylistSummary(
            id: playlist.id,
            name: playlist.name,
            comment: playlist.comment,
            owner: playlist.owner,
            coverArt: playlist.coverArt,
            songCount: playlist.songCount,
            duration: playlist.duration,
            created: playlist.created,
            changed: playlist.changed,
            isPublic: playlist.isPublic,
            isReadonly: playlist.isReadonly,
            validUntil: playlist.validUntil
        )
    }
}
