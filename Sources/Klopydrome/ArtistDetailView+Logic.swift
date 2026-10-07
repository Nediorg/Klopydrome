import Foundation
import NavidromeClient

extension ArtistDetailView {
    func processSearchSongs(
        _ songs: [SubsonicSong],
        artistID: String,
        name: String
    ) -> (lead: [SubsonicSong], appearsOn: [SubsonicAlbum]) {
        let ownAlbumIDs = Set(albums.map(\.id))
        var lead: [SubsonicSong] = []
        var guest: [String: SubsonicSong] = [:]

        for song in songs {
            let matches = song.artistId == artistID ||
                song.artist?.localizedCaseInsensitiveCompare(name) == .orderedSame ||
                song.albumArtistId == artistID ||
                song.albumArtist?.localizedCaseInsensitiveCompare(name) == .orderedSame
            guard matches else { continue }

            let albumID = song.albumId ?? ""
            let isLead = ownAlbumIDs.contains(albumID) ||
                song.albumArtistId == artistID ||
                song.albumArtist?.localizedCaseInsensitiveCompare(name) == .orderedSame

            if isLead {
                lead.append(song)
            } else if !albumID.isEmpty, !ownAlbumIDs.contains(albumID), guest[albumID] == nil {
                guest[albumID] = song
            }
        }

        let guestAlbums = guest.values.compactMap { song -> SubsonicAlbum? in
            guard let id = song.albumId, !id.isEmpty else { return nil }
            return SubsonicAlbum(
                id: id,
                title: song.album,
                album: song.album,
                artist: song.albumArtist,
                coverArt: song.coverArt
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return (lead, guestAlbums)
    }

    func userAffinityScore(for song: SubsonicSong) -> Double {
        let plays = Double(song.playCount ?? 0)
        let rating = app.effectiveRating(for: song)
        let isStarred = song.starred != nil || app.isStarred(song)

        let ratingPoints: Double
        switch rating {
        case 5: ratingPoints = 100.0
        case 4: ratingPoints = 60.0
        case 3: ratingPoints = 20.0
        case 2: ratingPoints = -50.0
        case 1: ratingPoints = -100.0
        default: ratingPoints = 0.0
        }

        let starPoints: Double = isStarred ? (rating == 0 ? 80.0 : 30.0) : 0.0
        let playPoints: Double = plays * 3.0

        return ratingPoints + starPoints + playPoints
    }

    func sortTopSongs(_ songs: [SubsonicSong]) -> [SubsonicSong] {
        songs.sorted { firstSong, secondSong in
            let score1 = userAffinityScore(for: firstSong)
            let score2 = userAffinityScore(for: secondSong)
            if score1 != score2 { return score1 > score2 }

            let rating1 = app.effectiveRating(for: firstSong)
            let rating2 = app.effectiveRating(for: secondSong)
            if rating1 != rating2 { return rating1 > rating2 }

            let star1 = (firstSong.starred != nil || app.isStarred(firstSong)) ? 1 : 0
            let star2 = (secondSong.starred != nil || app.isStarred(secondSong)) ? 1 : 0
            if star1 != star2 { return star1 > star2 }

            let plays1 = firstSong.playCount ?? 0
            let plays2 = secondSong.playCount ?? 0
            if plays1 != plays2 { return plays1 > plays2 }

            let disc1 = firstSong.discNumber ?? 1
            let disc2 = secondSong.discNumber ?? 1
            if disc1 != disc2 { return disc1 < disc2 }

            return (firstSong.track ?? 0) < (secondSong.track ?? 0)
        }
    }

    func loadOfflineArtist() {
        let artistID = artist.id
        let artistName = artist.name

        var allOfflineSongs = app.downloadedSongs
        let playlistSongs = app.library.playlistDetails.values.compactMap(\.entry).flatMap { $0 }
        let knownIDs = Set(allOfflineSongs.map(\.id))
        for song in playlistSongs where !knownIDs.contains(song.id) {
            allOfflineSongs.append(song)
        }

        let matchingSongs = allOfflineSongs.filter { song in
            song.artistId == artistID ||
            song.albumArtistId == artistID ||
            (song.artist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame) ||
            (song.albumArtist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame)
        }

        let matchingAlbums = app.library.albums.filter { album in
            album.artistId == artistID ||
            (album.artist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame)
        }

        let guestAlbumIDs = Set(matchingSongs.compactMap { song -> String? in
            let isLead = song.artistId == artistID ||
                         song.albumArtistId == artistID ||
                         (song.albumArtist?.localizedCaseInsensitiveCompare(artistName) == .orderedSame)
            if !isLead, let albId = song.albumId ?? song.parent {
                return albId
            }
            return nil
        })
        let guestAlbums = app.library.albums.filter { album in
            guestAlbumIDs.contains(album.id) && !matchingAlbums.contains(where: { $0.id == album.id })
        }

        allSongs = matchingSongs
        topSongs = Array(sortTopSongs(matchingSongs).prefix(27))
        appearsOn = guestAlbums

        let cover = matchingAlbums.first?.coverArt ?? matchingSongs.first?.coverArt ?? artist.artistImageUrl

        detail = ArtistDetail(
            id: artistID,
            name: artistName,
            coverArt: cover,
            albumCount: matchingAlbums.count,
            artistImageUrl: artist.artistImageUrl,
            album: matchingAlbums
        )
    }
}
