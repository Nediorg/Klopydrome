import XCTest
@testable import NavidromeClient

final class DecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> SubsonicEnvelope {
        try decoder.decode(SubsonicResponse.self, from: Data(json.utf8)).subsonicResponse
    }

    func testAlbumList2() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
          "serverVersion":"0.54.4","openSubsonic":true,
          "albumList2":{"album":[
            {"id":"a1","name":"Album Title","title":"Album Title","artist":"Artist Name",
             "artistId":"ar1","coverArt":"ca1","songCount":11,"duration":2400,
             "playCount":42,"created":"2023-01-01T00:00:00Z","year":1977,
             "genre":"Rock","starred":"2023-01-01T00:00:00Z"}
          ]}}}
        """
        let env = try decode(json)
        let albums = env.albumList2?.album ?? []
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].displayName, "Album Title")
        XCTAssertEqual(albums[0].artist, "Artist Name")
        XCTAssertEqual(albums[0].songCount, 11)
        XCTAssertEqual(albums[0].year, 1977)
        XCTAssertEqual(albums[0].starred, "2023-01-01T00:00:00Z")
    }

    func testSearch3() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "searchResult3":{
            "artist":[{"id":"ar1","name":"Artist Name","albumCount":5}],
            "album":[{"id":"al1","name":"Album Title","artist":"Artist Name","coverArt":"c1"}],
            "song":[{"id":"s1","title":"Song Title","artist":"Artist Name",
                     "album":"Album Title","duration":259,"coverArt":"c1","suffix":"mp3",
                     "track":1,"discNumber":1}]}}}
        """
        let env = try decode(json)
        let result = env.searchResult3
        XCTAssertEqual(result?.artist?.count, 1)
        XCTAssertEqual(result?.artist?.first?.name, "Artist Name")
        XCTAssertEqual(result?.song?.first?.duration, 259)
        XCTAssertEqual(result?.song?.first?.track, 1)
    }

    func testPlaylistsAndDetail() throws {
        let listJson = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "playlists":{"playlist":[
            {"id":"p1","name":"Road Trip","owner":"alice","songCount":20,"duration":6000,"public":true}
          ]}}}
        """
        let env = try decode(listJson)
        let summary = env.playlists?.playlist?.first
        XCTAssertEqual(summary?.displayName, "Road Trip")
        XCTAssertEqual(summary?.isPublic, true)

        let detailJson = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "playlist":{"id":"p1","name":"Road Trip","owner":"alice","songCount":1,"duration":120,
            "entry":[{"id":"s1","title":"Song","artist":"A","album":"B","duration":120}]}}}
        """
        let detail = try decode(detailJson).playlist
        XCTAssertEqual(detail?.entry?.count, 1)
        XCTAssertEqual(detail?.entry?.first?.title, "Song")
    }

    func testLyricsBySongIdSynced() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
          "serverVersion":"0.54.4","openSubsonic":true,
          "lyricsList":{"structuredLyrics":[
            {"displayArtist":"Artist Name","displayTitle":"Song Title","synced":true,"lang":"eng",
             "line":[{"start":0,"value":"First line"},
                     {"start":1200,"value":"Second line"},
                     {"start":2400,"value":"Third line"}]}
          ]}}}
        """
        let env = try decode(json)
        // Navidrome serves synced lyrics under `structuredLyrics`, not `lyrics`.
        let entry = env.lyricsList?.structuredLyrics?.first
        XCTAssertEqual(entry?.synced, true)
        XCTAssertEqual(entry?.lang, "eng")
        XCTAssertEqual(entry?.line?.count, 3)
        XCTAssertEqual(entry?.line?[1].start, 1200)
        XCTAssertEqual(entry?.line?[2].value, "Third line")
    }

    func testLyricsBySongIdLegacyCells() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "lyricsList":{"lyrics":[
            {"artist":"Artist Name","title":"Song Title","synced":true,
             "line":[{"start":0,"value":"First line"},
                     {"start":1200,"value":"Second line"}]}
          ]}}}
        """
        let env = try decode(json)
        let entry = env.lyricsList?.lyrics?.first
        XCTAssertEqual(entry?.synced, true)
        XCTAssertEqual(entry?.line?.count, 2)
        XCTAssertEqual(entry?.line?[1].start, 1200)
    }

    /// Mirrors real Navidrome output for an LRC with an `[offset:]` tag: the
    /// offset comes back as its own field in ms and the line starts are NOT
    /// adjusted — the client must apply it.
    func testLyricsBySongIdOffsetPassedThrough() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
          "serverVersion":"0.54.4","openSubsonic":true,
          "lyricsList":{"structuredLyrics":[
            {"synced":true,"lang":"eng","offset":-100,
             "line":[{"start":18800,"value":"Line one"},
                     {"start":22801,"value":"Line two"}]}
          ]}}}
        """
        let env = try decode(json)
        let entry = env.lyricsList?.structuredLyrics?.first
        XCTAssertEqual(entry?.offset, -100)
        // Starts stay untouched by the server; the client applies the offset.
        XCTAssertEqual(entry?.line?[0].start, 18_800)
        XCTAssertEqual(entry?.line?[1].start, 22_801)
    }

    func testLyricsClassic() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "lyrics":{"artist":"Artist Name","title":"Song Title","value":"Line one\\nLine two"}}}
        """
        let env = try decode(json)
        XCTAssertEqual(env.lyrics?.value, "Line one\nLine two")
    }

    func testGetArtists() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
          "artists":{"ignoredArticles":"The","index":[
            {"name":"A","artist":[{"id":"ar1","name":"Artist Alpha","albumCount":4}]},
            {"name":"B","artist":[{"id":"ar2","name":"Artist Beta","albumCount":3}]}
          ]}}}
        """
        let env = try decode(json)
        XCTAssertEqual(env.artists?.index?.count, 2)
        XCTAssertEqual(env.artists?.index?[0].artist?.first?.name, "Artist Alpha")
    }

    func testErrorResponse() throws {
        let json = """
        {"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome",
          "serverVersion":"0.54.4","error":{"code":40,"message":"Wrong username or password"}}}
        """
        let env = try decode(json)
        XCTAssertEqual(env.status, "failed")
        XCTAssertEqual(env.error?.code, 40)
    }

    /// The getAlbumInfo2 response nests its payload under `albumInfo` (not
    /// `albumInfo2`) — mirroring real Navidrome output so the Discord cover-art
    /// flow keeps decoding the image URLs.
    func testGetAlbumInfo2PayloadKey() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
          "serverVersion":"0.61.2","openSubsonic":true,
          "albumInfo":{
            "notes":"Notes",
            "musicBrainzId":"6e1d48f7-717c-416e-af35-5d2454a13af2",
            "smallImageUrl":"https://music.example.com/share/img/small?size=300",
            "mediumImageUrl":"https://music.example.com/share/img/medium?size=600",
            "largeImageUrl":"https://music.example.com/share/img/large?size=1200"
          }}}
        """
        let info = try decode(json).albumInfo
        XCTAssertEqual(info?.largeImageUrl, "https://music.example.com/share/img/large?size=1200")
        XCTAssertEqual(info?.mediumImageUrl, "https://music.example.com/share/img/medium?size=600")
        XCTAssertEqual(info?.smallImageUrl, "https://music.example.com/share/img/small?size=300")
    }

    /// Canonical now-playing subtitle template shared by the LCD, mini player,
    /// queue and song rows: "Artist — Album", degrading to whichever part exists.
    func testSongDisplaySubtitle() {
        XCTAssertEqual(
            SubsonicSong(id: "s1", title: "Song Title", album: "Album Title",
                         artist: "Artist Name").displaySubtitle,
            "Artist Name — Album Title")
        XCTAssertEqual(SubsonicSong(id: "s1", artist: "Artist Name").displaySubtitle, "Artist Name")
        XCTAssertEqual(SubsonicSong(id: "s1", album: "Album Title").displaySubtitle, "Album Title")
        XCTAssertEqual(SubsonicSong(id: "s1").displaySubtitle, "")
    }
}