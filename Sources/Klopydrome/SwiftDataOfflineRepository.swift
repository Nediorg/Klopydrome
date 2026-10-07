import Foundation
import SwiftData
import NavidromeClient

@ModelActor
public actor SwiftDataOfflineRepository: OfflineRepository {

    public func saveTrack(_ song: SubsonicSong) async throws {
        _ = try findOrCreateTrack(from: song, isExplicitDownload: true)
        try modelContext.save()
    }

    public func removeTrack(id: String) async throws {
        let descriptor = FetchDescriptor<OfflineTrack>(predicate: #Predicate { $0.id == id })
        if let track = try modelContext.fetch(descriptor).first {
            track.isDownloaded = false
            if track.playlistEntries.isEmpty && track.album == nil {
                modelContext.delete(track)
            }
            try modelContext.save()
        }
    }

    public func fetchDownloadedTracks() async throws -> [SubsonicSong] {
        let descriptor = FetchDescriptor<OfflineTrack>(
            predicate: #Predicate { $0.isDownloaded },
            sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
        )
        let tracks = try modelContext.fetch(descriptor)
        return tracks.map { mapTrackToSong($0) }
    }

    public func saveAlbumDetail(_ detail: AlbumDetail) async throws {
        let albumID = detail.id
        let descriptor = FetchDescriptor<OfflineAlbum>(predicate: #Predicate { $0.id == albumID })
        let album = try modelContext.fetch(descriptor).first ?? OfflineAlbum(
            id: detail.id,
            title: detail.name ?? "Untitled"
        )
        updateAlbumMetadata(album, from: detail)

        if let songs = detail.song {
            for song in songs {
                let track = try findOrCreateTrack(from: song, isExplicitDownload: false)
                track.album = album
                if track.albumID == nil {
                    track.albumID = album.id
                }
            }
        }

        modelContext.insert(album)
        try modelContext.save()
    }

    public func fetchAlbumDetail(id: String) async throws -> AlbumDetail? {
        let descriptor = FetchDescriptor<OfflineAlbum>(predicate: #Predicate { $0.id == id })
        guard let album = try modelContext.fetch(descriptor).first else { return nil }

        let tracksDesc = FetchDescriptor<OfflineTrack>(
            predicate: #Predicate { $0.albumID == id },
            sortBy: [
                SortDescriptor(\.discNumber, order: .forward),
                SortDescriptor(\.trackNumber, order: .forward)
            ]
        )
        let tracks = try modelContext.fetch(tracksDesc)
        let songs = tracks.map { mapTrackToSong($0) }

        return AlbumDetail(
            id: album.id,
            name: album.title,
            artist: album.artistName,
            artistId: album.artistID,
            coverArt: album.coverArt,
            songCount: album.songCount ?? tracks.count,
            duration: album.duration,
            year: album.year,
            genre: album.genre,
            recordType: album.recordType,
            musicBrainzId: album.musicBrainzId,
            starred: album.starred,
            song: songs.isEmpty ? nil : songs
        )
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
            for (index, song) in songs.enumerated() {
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

                let track = try findOrCreateTrack(from: song, isExplicitDownload: false)
                entry.track = track
                modelContext.insert(entry)
                playlist.entries.append(entry)
            }
        }

        modelContext.insert(playlist)
        try modelContext.save()
    }

    public func fetchPlaylistDetail(id: String) async throws -> PlaylistDetail? {
        let desc = FetchDescriptor<OfflinePlaylist>(predicate: #Predicate { $0.id == id })
        guard let playlist = try modelContext.fetch(desc).first else { return nil }

        let sortedEntries = playlist.entries.sorted { $0.index < $1.index }
        let songs: [SubsonicSong] = sortedEntries.map { entry in
            if let track = entry.track {
                return mapTrackToSong(track)
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

    public func fetchAlbums() async throws -> [SubsonicAlbum] {
        let desc = FetchDescriptor<OfflineAlbum>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        let albums = try modelContext.fetch(desc)
        return albums.map { mapAlbumToSubsonic($0) }
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
            let hasMatchingTrack = playlist.entries.contains { entry in
                guard let id = entry.trackID ?? entry.track?.id else { return false }
                return downloadedIDs.contains(id)
            }
            guard hasMatchingTrack else { return nil }
            return mapPlaylistToSummary(playlist)
        }
    }

    public func fetchArtists() async throws -> [Artist] {
        let desc = FetchDescriptor<OfflineArtist>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let artists = try modelContext.fetch(desc)
        return artists.map { artist in
            Artist(
                id: artist.id,
                name: artist.name,
                albumCount: artist.albumCount ?? artist.albums.count,
                artistImageUrl: artist.artistImageUrl,
                starred: artist.starred
            )
        }
    }

    public func clearAll() async throws {
        let entries = try modelContext.fetch(FetchDescriptor<OfflinePlaylistEntry>())
        for entry in entries { modelContext.delete(entry) }

        let playlists = try modelContext.fetch(FetchDescriptor<OfflinePlaylist>())
        for playlist in playlists { modelContext.delete(playlist) }

        let tracks = try modelContext.fetch(FetchDescriptor<OfflineTrack>())
        for track in tracks { modelContext.delete(track) }

        let albums = try modelContext.fetch(FetchDescriptor<OfflineAlbum>())
        for album in albums { modelContext.delete(album) }

        let artists = try modelContext.fetch(FetchDescriptor<OfflineArtist>())
        for artist in artists { modelContext.delete(artist) }

        try modelContext.save()
    }
}

// MARK: - Private Helpers

extension SwiftDataOfflineRepository {
    @discardableResult
    private func findOrCreateTrack(
        from song: SubsonicSong,
        isExplicitDownload: Bool
    ) throws -> OfflineTrack {
        let songID = song.id
        let descriptor = FetchDescriptor<OfflineTrack>(predicate: #Predicate { $0.id == songID })
        let existing = try modelContext.fetch(descriptor).first
        let track = existing ?? OfflineTrack(id: song.id, title: song.title ?? "Untitled")
        updateTrackMetadata(track, from: song)
        if isExplicitDownload {
            track.isDownloaded = true
        }

        if let albumIdentifier = song.albumId ?? song.parent {
            track.album = try findOrCreateAlbum(id: albumIdentifier, from: song)
        }

        let artistIdentifier = song.artistId ?? song.albumArtistId ?? song.artist ?? "Unknown"
        track.artist = try findOrCreateArtist(id: artistIdentifier, from: song)

        modelContext.insert(track)
        return track
    }

    private func findOrCreateAlbum(id: String, from song: SubsonicSong) throws -> OfflineAlbum {
        let descriptor = FetchDescriptor<OfflineAlbum>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let album = OfflineAlbum(id: id, title: song.album ?? "Unknown Album")
        album.artistName = song.albumArtist ?? song.artist
        album.artistID = song.artistId
        album.coverArt = song.coverArt
        album.year = song.year
        album.genre = song.genre
        modelContext.insert(album)
        return album
    }

    private func findOrCreateArtist(id: String, from song: SubsonicSong) throws -> OfflineArtist {
        let descriptor = FetchDescriptor<OfflineArtist>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let artistName = song.artist ?? song.albumArtist ?? "Unknown Artist"
        let artist = OfflineArtist(id: id, name: artistName)
        artist.artistImageUrl = nil
        modelContext.insert(artist)
        return artist
    }

    private func updateTrackMetadata(_ track: OfflineTrack, from song: SubsonicSong) {
        track.title = song.title ?? "Untitled"
        track.albumTitle = song.album
        track.artistName = song.artist
        track.albumArtistName = song.albumArtist
        track.trackNumber = song.track
        track.discNumber = song.discNumber
        track.year = song.year
        track.genre = song.genre
        track.coverArt = song.coverArt
        track.size = song.size
        track.contentType = song.contentType
        track.suffix = song.suffix
        track.duration = song.duration
        track.bitRate = song.bitRate
        track.path = song.path
        track.playCount = song.playCount
        track.starred = song.starred
        track.userRating = song.userRating
        track.averageRating = song.averageRating
        track.albumID = song.albumId ?? song.parent
        track.artistID = song.artistId
        track.albumArtistID = song.albumArtistId
        track.musicBrainzId = song.musicBrainzId
    }

    private func updateAlbumMetadata(_ album: OfflineAlbum, from detail: AlbumDetail) {
        album.title = detail.name ?? album.title
        album.artistName = detail.artist ?? album.artistName
        album.artistID = detail.artistId ?? album.artistID
        album.coverArt = detail.coverArt ?? album.coverArt
        album.songCount = detail.songCount ?? album.songCount
        album.duration = detail.duration ?? album.duration
        album.year = detail.year ?? album.year
        album.genre = detail.genre ?? album.genre
        album.starred = detail.starred ?? album.starred
        album.recordType = detail.recordType ?? album.recordType
        album.musicBrainzId = detail.musicBrainzId ?? album.musicBrainzId
        album.updatedAt = Date()
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

    private func mapTrackToSong(_ track: OfflineTrack) -> SubsonicSong {
        SubsonicSong(
            id: track.id,
            parent: track.albumID,
            title: track.title,
            album: track.albumTitle,
            artist: track.artistName,
            track: track.trackNumber,
            year: track.year,
            genre: track.genre,
            coverArt: track.coverArt,
            size: track.size,
            contentType: track.contentType,
            suffix: track.suffix,
            duration: track.duration,
            bitRate: track.bitRate,
            path: track.path,
            playCount: track.playCount,
            discNumber: track.discNumber,
            starred: track.starred,
            userRating: track.userRating,
            averageRating: track.averageRating,
            albumId: track.albumID,
            artistId: track.artistID,
            albumArtist: track.albumArtistName,
            albumArtistId: track.albumArtistID,
            musicBrainzId: track.musicBrainzId
        )
    }

    private func mapAlbumToSubsonic(_ album: OfflineAlbum) -> SubsonicAlbum {
        SubsonicAlbum(
            id: album.id,
            title: album.title,
            album: album.title,
            name: album.title,
            artist: album.artistName,
            artistId: album.artistID,
            coverArt: album.coverArt,
            songCount: album.songCount,
            duration: album.duration,
            year: album.year,
            genre: album.genre,
            starred: album.starred,
            recordType: album.recordType,
            musicBrainzId: album.musicBrainzId
        )
    }

    private func mapPlaylistToSummary(_ playlist: OfflinePlaylist) -> PlaylistSummary {
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
