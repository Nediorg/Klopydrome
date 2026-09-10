import Foundation
import NavidromeClient

/// A queryable field in the smart-playlist DSL. Covers the canonical server
/// field set (song, album and artist columns plus MusicBrainz IDs and tag/role
/// names), so server-side Navidrome rules round-trip losslessly through the
/// local editor.
///
/// `rawValue` is the server DSL key. `custom` is a placeholder for fields the
/// app does not know (e.g. user-defined tags); its real DSL name is kept in
/// `QueryRule.customField`.
enum QueryField: String, CaseIterable, Identifiable, Hashable {

    // MARK: Text

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

    // MARK: Numeric

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

    // MARK: Boolean

    case loved = "loved"
    case albumLoved = "albumloved"
    case artistLoved = "artistloved"
    case hasCoverArt = "hascoverart"
    case compilation = "compilation"
    case explicit = "explicit"
    case missing = "missing"

    // MARK: Dates

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

    // MARK: References

    case mbzAlbumID = "mbz_album_id"
    case mbzAlbumArtistID = "mbz_album_artist_id"
    case mbzArtistID = "mbz_artist_id"
    case mbzRecordingID = "mbz_recording_id"
    case mbzReleaseTrackID = "mbz_release_track_id"
    case mbzReleaseGroupID = "mbz_release_group_id"
    case libraryID = "library_id"

    /// Value is the id of another playlist (operator `inPlaylist`/`notInPlaylist`).
    case playlistID = "id"

    /// Sort-only pseudo-field ("случайный порядок"), never a rule field.
    case random = "random"

    /// Fallback for unknown fields; kept using `QueryRule.customField`.
    case custom

    var id: String { rawValue }

    // MARK: Category / style

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

    // MARK: Label

    var label: String {
        switch self {
        case .title: return "Название"
        case .album: return "Альбом"
        case .artist: return "Исполнитель"
        case .artistRole: return "Исполнитель альбома"
        case .genre: return "Жанр"
        case .mood: return "Настроение"
        case .comment: return "Комментарий"
        case .lyrics: return "Текст песни"
        case .albumComment: return "Комментарий альбома"
        case .catalogNumber: return "Каталожный номер"
        case .discSubtitle: return "Подзаголовок диска"
        case .filePath: return "Путь к файлу"
        case .fileType: return "Тип файла"
        case .codec: return "Кодек"
        case .sortTitle: return "Сорт. название"
        case .sortAlbum: return "Сорт. альбом"
        case .sortArtist: return "Сорт. исполнитель"
        case .sortAlbumArtist: return "Сорт. исполнитель альбома"
        case .composer: return "Композитор"
        case .conductor: return "Дирижёр"
        case .performer: return "Исполнитель (роль)"
        case .producer: return "Продюсер"
        case .remixer: return "Ремиксер"
        case .writer: return "Автор"
        case .lyricist: return "Автор слов"
        case .albumType: return "Тип альбома"
        case .trackNumber: return "Номер трека"
        case .discNumber: return "Номер диска"
        case .year: return "Год"
        case .originalYear: return "Оригинальный год"
        case .releaseYear: return "Год релиза"
        case .duration: return "Длительность (сек)"
        case .size: return "Размер (байт)"
        case .bitrate: return "Битрейт"
        case .bitDepth: return "Битовая глубина"
        case .sampleRate: return "Частота дискретизации"
        case .bpm: return "Темп (BPM)"
        case .channels: return "Каналов"
        case .playCount: return "Прослушиваний"
        case .rating: return "Моя оценка"
        case .averageRating: return "Средняя оценка"
        case .albumRating: return "Оценка альбома"
        case .albumPlayCount: return "Прослушиваний альбома"
        case .albumSongCount: return "Песен в альбоме"
        case .albumSize: return "Размер альбома"
        case .albumDuration: return "Длительность альбома"
        case .artistRating: return "Оценка исполнителя"
        case .artistPlayCount: return "Прослушиваний исполнителя"
        case .rgaAlbumGain: return "Реигейн альбома (гейн)"
        case .rgaAlbumPeak: return "Реигейн альбома (пик)"
        case .rgaTrackGain: return "Реигейн трека (гейн)"
        case .rgaTrackPeak: return "Реигейн трека (пик)"
        case .loved: return "Люблю (избранное)"
        case .albumLoved: return "Люблю альбом"
        case .artistLoved: return "Люблю исполнителя"
        case .hasCoverArt: return "Есть обложка"
        case .compilation: return "Сборник"
        case .explicit: return "18+ (explicit)"
        case .missing: return "Файл отсутствует"
        case .date: return "Дата"
        case .originalDate: return "Оригинальная дата"
        case .releaseDate: return "Дата релиза"
        case .dateAdded: return "Добавлено"
        case .dateModified: return "Изменено"
        case .lastPlayed: return "Последнее прослушивание"
        case .dateLoved: return "Когда добавлено в избранное"
        case .dateRated: return "Когда оценено"
        case .albumDateAdded: return "Альбом добавлен"
        case .albumDateModified: return "Альбом изменён"
        case .albumDateLoved: return "Альбом добавлен в избранное"
        case .albumDateRated: return "Альбом оценён"
        case .albumLastPlayed: return "Альбом прослушан"
        case .artistDateLoved: return "Исполнитель в избранном"
        case .artistDateRated: return "Исполнитель оценён"
        case .artistLastPlayed: return "Исполнитель прослушан"
        case .mbzAlbumID: return "MusicBrainz альбом"
        case .mbzAlbumArtistID: return "MusicBrainz исполнитель альбома"
        case .mbzArtistID: return "MusicBrainz исполнитель"
        case .mbzRecordingID: return "MusicBrainz запись"
        case .mbzReleaseTrackID: return "MusicBrainz трек релиза"
        case .mbzReleaseGroupID: return "MusicBrainz группа релизов"
        case .libraryID: return "Библиотека"
        case .playlistID: return "Плейлист"
        case .random: return "Случайно"
        case .custom: return "Прочее"
        }
    }

    /// Fields the rule editor offers. Excludes the custom fallback and the
    /// sort-only random row.
    static var pickerCases: [QueryField] {
        allCases.filter { $0 != .custom && $0 != .random }
    }

    // MARK: DSL

    var dsl: String {
        if self == .custom { return "custom" }
        return rawValue
    }

    init?(dsl: String) {
        if let field = QueryField(rawValue: dsl) {
            self = field
        } else if dsl == "playCount" {
            // Legacy local queries used a capitalised alias; accept it.
            self = .playCount
        } else if dsl == "starred" {
            // Legacy local queries used the Subsonic "starred" name.
            self = .loved
        } else {
            return nil
        }
    }

    // MARK: Local evaluation

    /// Reads the song's field value for local (client-side) evaluation.
    /// Returns nil for fields the local model does not carry — rules using them
    /// simply match nothing locally, while the server still evaluates them.
    func value(from song: SubsonicSong) -> QueryValue? {
        Self.readers[self]?(song)
    }

    /// Per-field local readers. Kept as a static table so two dozen mappings
    /// don't blow past the cyclomatic budget of a single switch.
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

    /// Normalises a Subsonic timestamp to its `YYYY-MM-DD` date component.
    static func datePart(of value: String) -> String? {
        let prefix = String(value.prefix(10))
        return prefix.count == 10 ? prefix : nil
    }
}

extension QueryField {
    /// Operators offered for a field, grouped by its value style, mirroring
    var allowedOperators: [QueryOperator] {
        switch style {
        case .playlist: return [.inPlaylist, .notInPlaylist]
        case .boolean: return [.is_, .isNot, .isMissing, .isPresent]
        case .number: return [.is_, .isNot, .gt, .lt, .inTheRange, .isMissing, .isPresent]
        case .date: return [.is_, .isNot, .before, .after, .inTheLast, .notInTheLast, .isMissing, .isPresent]
        case .string: return [.is_, .isNot, .contains, .notContains, .startsWith, .endsWith, .isMissing, .isPresent]
        case .sort: return []
        }
    }
}
