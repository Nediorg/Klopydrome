import Foundation
import NavidromeClient

enum QueryField: String, CaseIterable, Identifiable, Hashable {

    case title = "title"
    case album = "album"
    case artist = "artist"
    case artistRole = "albumartist"
    case genre = "genre"
    case mood = "mood"
    case comment = "comment"
    case lyrics = "lyrics"
    case albumComment = "albumcomment"
    case catalogNumber = "catalognumber"
    case discSubtitle = "discsubtitle"
    case filePath = "filepath"
    case fileType = "filetype"
    case codec = "codec"
    case sortTitle = "sorttitle"
    case sortAlbum = "sortalbum"
    case sortArtist = "sortartist"
    case sortAlbumArtist = "sortalbumartist"
    case composer = "composer"
    case conductor = "conductor"
    case performer = "performer"
    case producer = "producer"
    case remixer = "remixer"
    case writer = "writer"
    case lyricist = "lyricist"
    case albumType = "albumtype"

    case trackNumber = "tracknumber"
    case discNumber = "discnumber"
    case year = "year"
    case originalYear = "originalyear"
    case releaseYear = "releaseyear"
    case duration = "duration"
    case size = "size"
    case bitrate = "bitrate"
    case bitDepth = "bitdepth"
    case sampleRate = "samplerate"
    case bpm = "bpm"
    case channels = "channels"
    case playCount = "playcount"
    case rating = "rating"
    case averageRating = "averagerating"
    case albumRating = "albumrating"
    case albumPlayCount = "albumplaycount"
    case albumSongCount = "albumsongcount"
    case albumSize = "albumsize"
    case albumDuration = "albumduration"
    case artistRating = "artistrating"
    case artistPlayCount = "artistplaycount"
    case rgaAlbumGain = "rgalbumgain"
    case rgaAlbumPeak = "rgalbumpeak"
    case rgaTrackGain = "rgtrackgain"
    case rgaTrackPeak = "rgtrackpeak"

    case loved = "loved"
    case albumLoved = "albumloved"
    case artistLoved = "artistloved"
    case hasCoverArt = "hascoverart"
    case compilation = "compilation"
    case explicit = "explicit"
    case missing = "missing"

    case date = "date"
    case originalDate = "originaldate"
    case releaseDate = "releasedate"
    case dateAdded = "dateadded"
    case dateModified = "datemodified"
    case lastPlayed = "lastplayed"
    case dateLoved = "dateloved"
    case dateRated = "daterated"
    case albumDateAdded = "albumdateadded"
    case albumDateModified = "albumdatemodified"
    case albumDateLoved = "albumdateloved"
    case albumDateRated = "albumdaterated"
    case albumLastPlayed = "albumlastplayed"
    case artistDateLoved = "artistdateloved"
    case artistDateRated = "artistdaterated"
    case artistLastPlayed = "artistlastplayed"

    case mbzAlbumID = "mbz_album_id"
    case mbzAlbumArtistID = "mbz_album_artist_id"
    case mbzArtistID = "mbz_artist_id"
    case mbzRecordingID = "mbz_recording_id"
    case mbzReleaseTrackID = "mbz_release_track_id"
    case mbzReleaseGroupID = "mbz_release_group_id"
    case libraryID = "library_id"

    case playlistID = "id"

    case random = "random"

    case custom

    var id: String { rawValue }

    enum Style { case string, number, date, boolean, playlist, sort }

    var style: Style {
        switch self {
        case .title, .album, .artist, .artistRole, .genre, .mood, .comment, .lyrics,
                .albumComment, .catalogNumber, .discSubtitle, .filePath, .fileType,
                .codec, .sortTitle, .sortAlbum, .sortArtist, .sortAlbumArtist,
                .composer, .conductor, .performer, .producer, .remixer, .writer,
                .lyricist, .albumType, .mbzAlbumID, .mbzAlbumArtistID, .mbzArtistID,
                .mbzRecordingID, .mbzReleaseTrackID, .mbzReleaseGroupID, .libraryID:
            return .string
        case .trackNumber, .discNumber, .year, .originalYear, .releaseYear, .duration,
                .size, .bitrate, .bitDepth, .sampleRate, .bpm, .channels, .playCount,
                .rating, .averageRating, .albumRating, .albumPlayCount, .albumSongCount,
                .albumSize, .albumDuration, .artistRating, .artistPlayCount,
                .rgaAlbumGain, .rgaAlbumPeak, .rgaTrackGain, .rgaTrackPeak:
            return .number
        case .loved, .albumLoved, .artistLoved, .hasCoverArt, .compilation, .explicit, .missing:
            return .boolean
        case .date, .originalDate, .releaseDate, .dateAdded, .dateModified, .lastPlayed,
                .dateLoved, .dateRated, .albumDateAdded, .albumDateModified,
                .albumDateLoved, .albumDateRated, .albumLastPlayed, .artistDateLoved,
                .artistDateRated, .artistLastPlayed:
            return .date
        case .playlistID: return .playlist
        case .random, .custom: return .string
        }
    }

    var isNumeric: Bool { style == .number }
    var isBoolean: Bool { style == .boolean }
    var isDate: Bool { style == .date }

    var label: String {
        switch self {
        case .title: return "Name"
        case .album: return "Album"
        case .artist: return "Artist"
        case .artistRole: return "Album Artist"
        case .genre: return "Genre"
        case .mood: return "Mood"
        case .comment: return "Comment"
        case .lyrics: return "Song lyrics"
        case .albumComment: return "Album Comment"
        case .catalogNumber: return "Catalog Number"
        case .discSubtitle: return "Disc subtitle"
        case .filePath: return "File path"
        case .fileType: return "File Type"
        case .codec: return "Codec"
        case .sortTitle: return "Sort by title"
        case .sortAlbum: return "Sort by album"
        case .sortArtist: return "Sort by artist"
        case .sortAlbumArtist: return "Sort by album artist"
        case .composer: return "Composer"
        case .conductor: return "Conductor"
        case .performer: return "Artist (role)"
        case .producer: return "Producer"
        case .remixer: return "Remixer"
        case .writer: return "Author"
        case .lyricist: return "Lyricist"
        case .albumType: return "Album Type"
        case .trackNumber: return "Track Number"
        case .discNumber: return "Disc Number"
        case .year: return "Year"
        case .originalYear: return "Original Year"
        case .releaseYear: return "Release Year"
        case .duration: return "Duration (sec)"
        case .size: return "Size (bytes)"
        case .bitrate: return "Bitrate"
        case .bitDepth: return "Bit Depth"
        case .sampleRate: return "Sample Rate"
        case .bpm: return "Tempo (BPM)"
        case .channels: return "Channels"
        case .playCount: return "Plays"
        case .rating: return "My Rating"
        case .averageRating: return "Average rating"
        case .albumRating: return "Album Rating"
        case .albumPlayCount: return "Album plays"
        case .albumSongCount: return "Songs in Album"
        case .albumSize: return "Album size"
        case .albumDuration: return "Album Duration"
        case .artistRating: return "Artist Rating"
        case .artistPlayCount: return "Artist plays"
        case .rgaAlbumGain: return "Album ReplayGain (gain)"
        case .rgaAlbumPeak: return "Album ReplayGain (peak)"
        case .rgaTrackGain: return "Track ReplayGain (gain)"
        case .rgaTrackPeak: return "Track ReplayGain (peak)"
        case .loved: return "Loved (Favorites)"
        case .albumLoved: return "Loved Album"
        case .artistLoved: return "Loved Artist"
        case .hasCoverArt: return "Has Artwork"
        case .compilation: return "Compilation"
        case .explicit: return "Explicit (18+)"
        case .missing: return "File Missing"
        case .date: return "Date"
        case .originalDate: return "Original Date"
        case .releaseDate: return "Release Date"
        case .dateAdded: return "Added"
        case .dateModified: return "Modified"
        case .lastPlayed: return "Last played"
        case .dateLoved: return "When Added to Favorites"
        case .dateRated: return "When Rated"
        case .albumDateAdded: return "Album added"
        case .albumDateModified: return "Album changed"
        case .albumDateLoved: return "Album added to favorites"
        case .albumDateRated: return "Album rated"
        case .albumLastPlayed: return "Album played"
        case .artistDateLoved: return "Favorite artist"
        case .artistDateRated: return "Artist rated"
        case .artistLastPlayed: return "Artist played"
        case .mbzAlbumID: return "MusicBrainz album"
        case .mbzAlbumArtistID: return "MusicBrainz album artist"
        case .mbzArtistID: return "MusicBrainz artist"
        case .mbzRecordingID: return "MusicBrainz recording"
        case .mbzReleaseTrackID: return "MusicBrainz release track"
        case .mbzReleaseGroupID: return "MusicBrainz release group"
        case .libraryID: return "Library"
        case .playlistID: return "Playlist"
        case .random: return "Random"
        case .custom: return "Other"
        }
    }

    static var pickerCases: [QueryField] {
        allCases.filter { $0 != .custom && $0 != .random }
    }

    var dsl: String {
        if self == .custom { return "custom" }
        return rawValue
    }

    init?(dsl: String) {
        if let field = QueryField(rawValue: dsl) {
            self = field
        } else if dsl == "playCount" {
            self = .playCount
        } else if dsl == "starred" {
            self = .loved
        } else {
            return nil
        }
    }

    func value(from song: SubsonicSong) -> QueryValue? {
        Self.readers[self]?(song)
    }

    private static let readers: [QueryField: (SubsonicSong) -> QueryValue?] = [
        .title: { $0.title.map(QueryValue.init(text:)) },
        .album: { $0.album.map(QueryValue.init(text:)) },
        .artist: { $0.artist.map(QueryValue.init(text:)) },
        .artistRole: { $0.albumArtist.map(QueryValue.init(text:)) },
        .genre: { $0.genre.map(QueryValue.init(text:)) },
        .mood: { $0.genre.map(QueryValue.init(text:)) },
        .filePath: { $0.path.map(QueryValue.init(text:)) },
        .fileType: { $0.suffix.map(QueryValue.init(text:)) },
        .codec: { $0.suffix.map(QueryValue.init(text:)) },
        .mbzRecordingID: { $0.musicBrainzId.map(QueryValue.init(text:)) },
        .trackNumber: { $0.track.map { QueryValue(number: Double($0)) } },
        .discNumber: { $0.discNumber.map { QueryValue(number: Double($0)) } },
        .year: { $0.year.map { QueryValue(number: Double($0)) } },
        .duration: { $0.duration.map { QueryValue(number: Double($0)) } },
        .size: { $0.size.map { QueryValue(number: Double($0)) } },
        .bitrate: { $0.bitRate.map { QueryValue(number: Double($0)) } },
        .playCount: { $0.playCount.map { QueryValue(number: Double($0)) } },
        .rating: { $0.userRating.map { QueryValue(number: Double($0)) } },
        .averageRating: { $0.averageRating.map(QueryValue.init(number:)) },
        .loved: { song in QueryValue(number: (song.starred?.isEmpty == false) ? 1 : 0) },
        .dateAdded: { $0.created.flatMap(QueryField.datePart(of:)).flatMap(QueryValue.init(text:)) }
    ]

    static func datePart(of value: String) -> String? {
        let prefix = String(value.prefix(10))
        return prefix.count == 10 ? prefix : nil
    }
}

extension QueryField {
    var allowedOperators: [QueryOperator] {
        switch style {
        case .playlist: return [.inPlaylist, .notInPlaylist]
        case .boolean: return [.is, .isNot, .isMissing, .isPresent]
        case .number: return [.is, .isNot, .gt, .lt, .inTheRange, .isMissing, .isPresent]
        case .date: return [.is, .isNot, .before, .after, .inTheLast, .notInTheLast, .isMissing, .isPresent]
        case .string: return [.is, .isNot, .contains, .notContains, .startsWith, .endsWith, .isMissing, .isPresent]
        case .sort: return []
        }
    }
}
