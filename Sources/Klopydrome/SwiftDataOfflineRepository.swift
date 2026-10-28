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
            modelContext.delete(track)
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

    public func fetchTrackCount() throws -> Int {
        try modelContext.fetch(FetchDescriptor<OfflineTrack>()).count
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
            let minimalTracks = songs.map { MinimalAlbumTrack(from: $0) }
            album.tracksSummaryData = try? JSONEncoder().encode(minimalTracks)

            let songIDs = Set(songs.map(\.id))
            let downloadedDesc = FetchDescriptor<OfflineTrack>(
                predicate: #Predicate { $0.isDownloaded }
            )
            let downloadedTracks = try modelContext.fetch(downloadedDesc)
            for track in downloadedTracks where songIDs.contains(track.id) {
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

        let songs: [SubsonicSong]
        if let data = album.tracksSummaryData,
           let minimalTracks = try? JSONDecoder().decode([MinimalAlbumTrack].self, from: data) {
            let downloadedDesc = FetchDescriptor<OfflineTrack>(predicate: #Predicate { $0.isDownloaded })
            let downloadedTracks = try modelContext.fetch(downloadedDesc)
            let downloadedByID = Dictionary(
                downloadedTracks.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            songs = minimalTracks.map { minimal in
                if let downloaded = downloadedByID[minimal.id] {
                    return mapTrackToSong(downloaded)
                }
                return minimal.toSubsonicSong(album: album)
            }
        } else {
            let tracksDesc = FetchDescriptor<OfflineTrack>(
                predicate: #Predicate { $0.albumID == id },
                sortBy: [
                    SortDescriptor(\.discNumber, order: .forward),
                    SortDescriptor(\.trackNumber, order: .forward)
                ]
            )
            let tracks = try modelContext.fetch(tracksDesc)
            songs = tracks.map { mapTrackToSong($0) }
        }

        return AlbumDetail(
            id: album.id,
            name: album.title,
            artist: album.artistName,
            artistId: album.artistID,
            coverArt: album.coverArt,
            songCount: album.songCount ?? songs.count,
            duration: album.duration,
            year: album.year,
            genre: album.genre,
            recordType: album.recordType,
            musicBrainzId: album.musicBrainzId,
            starred: album.starred,
            song: songs.isEmpty ? nil : songs
        )
    }

    public func fetchAlbums() async throws -> [SubsonicAlbum] {
        let desc = FetchDescriptor<OfflineAlbum>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        let albums = try modelContext.fetch(desc)
        return albums.map { mapAlbumToSubsonic($0) }
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

    func mapTrackToSong(_ track: OfflineTrack) -> SubsonicSong {
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
}
