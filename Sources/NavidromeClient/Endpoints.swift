import Foundation

// MARK: - Endpoints

public extension SubsonicClient {

    // MARK: System

    func ping() async throws {
        _ = try await requestEnvelope(endpoint: "ping")
    }

    // MARK: Browsing

    func getArtists() async throws -> [ArtistIndex] {
        let envelope = try await requestEnvelope(endpoint: "getArtists")
        return envelope.artists?.index ?? []
    }

    func getArtist(id: String) async throws -> ArtistDetail {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let artist = try await requestEnvelope(endpoint: "getArtist", params: params).artist else {
            throw SubsonicError.server(code: 50, message: "Artist not found")
        }
        return artist
    }

    func getAlbum(id: String) async throws -> AlbumDetail {
        let params = [URLQueryItem(name: "id", value: id)]
        guard let album = try await requestEnvelope(endpoint: "getAlbum", params: params).album else {
            throw SubsonicError.server(code: 50, message: "Album not found")
        }
        return album
    }

    // MARK: Album / song lists

    func getAlbumList2(type: AlbumListType, size: Int = 100, offset: Int = 0,
                       musicFolderId: String? = nil) async throws -> [SubsonicAlbum] {
        var params = [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let musicFolderId {
            params.append(URLQueryItem(name: "musicFolderId", value: musicFolderId))
        }
        return try await requestEnvelope(endpoint: "getAlbumList2", params: params).albumList2?.album ?? []
    }

    /// All songs of a genre, paginated. Used by smart playlists.
    func getSongsByGenre(genre: String, count: Int = 50, offset: Int = 0) async throws -> [SubsonicSong] {
        let params = [
            URLQueryItem(name: "genre", value: genre),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        return try await requestEnvelope(endpoint: "getSongsByGenre", params: params).songsByGenre?.song ?? []
    }

    /// All genres on the server, best-effort (sorted by song count, then name).
    func getGenres() async throws -> [Genre] {
        let genres = try await requestEnvelope(endpoint: "getGenres").genres?.genre ?? []
        return genres.sorted {
            let lhsCount = $0.songCount ?? 0
            let rhsCount = $1.songCount ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return ($0.value ?? "").localizedCaseInsensitiveCompare($1.value ?? "") == .orderedAscending
        }
    }

    // MARK: Search

    func search3(query: String, artistCount: Int = 20, albumCount: Int = 20,
                 songCount: Int = 50, songOffset: Int = 0) async throws -> (artists: [Artist], albums: [SubsonicAlbum], songs: [SubsonicSong]) {
        var params = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: String(artistCount)),
            URLQueryItem(name: "albumCount", value: String(albumCount)),
            URLQueryItem(name: "songCount", value: String(songCount)),
        ]
        if songOffset > 0 {
            params.append(URLQueryItem(name: "songOffset", value: String(songOffset)))
        }
        let payload = try await requestEnvelope(endpoint: "search3", params: params).searchResult3
        return (payload?.artist ?? [], payload?.album ?? [], payload?.song ?? [])
    }

    // MARK: Starred / favorites

    func getStarred2() async throws -> (artists: [Artist], albums: [SubsonicAlbum], songs: [SubsonicSong]) {
        let payload = try await requestEnvelope(endpoint: "getStarred2").starred2
        return (payload?.artist ?? [], payload?.album ?? [], payload?.song ?? [])
    }

    func star(songIds: [String] = [], albumIds: [String] = [], artistIds: [String] = []) async throws {
        var params: [URLQueryItem] = []
        songIds.forEach { params.append(URLQueryItem(name: "id", value: $0)) }
        albumIds.forEach { params.append(URLQueryItem(name: "albumId", value: $0)) }
        artistIds.forEach { params.append(URLQueryItem(name: "artistId", value: $0)) }
        _ = try await requestEnvelope(endpoint: "star", params: params)
    }

    func unstar(songIds: [String] = [], albumIds: [String] = [], artistIds: [String] = []) async throws {
        var params: [URLQueryItem] = []
        songIds.forEach { params.append(URLQueryItem(name: "id", value: $0)) }
        albumIds.forEach { params.append(URLQueryItem(name: "albumId", value: $0)) }
        artistIds.forEach { params.append(URLQueryItem(name: "artistId", value: $0)) }
        _ = try await requestEnvelope(endpoint: "unstar", params: params)
    }

    func setRating(_ rating: Int, id: String) async throws {
        guard (0...5).contains(rating) else { return }
        let params = [
            URLQueryItem(name: "rating", value: String(rating)),
            URLQueryItem(name: "id", value: id),
        ]
        _ = try await requestEnvelope(endpoint: "setRating", params: params)
    }

    // MARK: Scrobble

    func scrobble(id: String, time: Date? = nil, submission: Bool = true) async throws {
        var params = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "submission", value: submission ? "true" : "false"),
        ]
        if let time {
            params.append(URLQueryItem(name: "time", value: String(Int(time.timeIntervalSince1970))))
        }
        _ = try await requestEnvelope(endpoint: "scrobble", params: params)
    }

    // MARK: Playlists

    func getPlaylists() async throws -> [PlaylistSummary] {
        try await requestEnvelope(endpoint: "getPlaylists").playlists?.playlist ?? []
    }

    /// Streaming load of a playlist. The server returns header + all songs in one
    /// JSON, so we decode it twice: first the small header envelope for instant
    /// display, then the `entry` array in bounded chunks so huge playlists paint
    /// progressively instead of waiting for one giant decode. Yields the header
    /// first, then one `PlaylistChunk.songs` per slice.
    func getPlaylistChunked(id: String, chunkSize: Int = 200) -> AsyncThrowingStream<PlaylistChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await requestData(
                        endpoint: "getPlaylist",
                        params: [URLQueryItem(name: "id", value: id)])
                    // First decode the thin envelope to get header + the raw entry array
                    // without decoding every song yet.
                    let envelope = try JSONDecoder().decode(SubsonicResponse.self, from: data).subsonicResponse
                    guard envelope.status == "ok" else {
                        if let error = envelope.error {
                            throw SubsonicError.server(code: error.code, message: error.message)
                        }
                        throw SubsonicError.server(code: 0, message: "Server returned status '\(envelope.status)'.")
                    }
                    guard let playlist = envelope.playlist else {
                        continuation.finish()
                        return
                    }
                    // Drive the header through without the whole song list.
                    let header = PlaylistDetail(
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
                        validUntil: playlist.validUntil)
                    continuation.yield(.header(header))

                    // Re-decode the raw JSON's entry array in chunks. Parse once,
                    // slice the top-level value, decode each slice separately so the
                    // first slice paints before the rest is decoded.
                    try await Self.streamPlaylistEntries(from: data, chunkSize: chunkSize) { songs in
                        continuation.yield(.songs(songs))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parses a `getPlaylist` response body once, then re-decodes its `entry`
    /// array in bounded slices, forwarding each decoded slice to `emit`.
    private static func streamPlaylistEntries(
        from data: Data,
        chunkSize: Int,
        emit: ([SubsonicSong]) throws -> Void
    ) async throws {
        // JSONSerialization for the light structural pass is much cheaper than
        // decoding thousands of deeply-nested song objects just to rediscover
        // the entry array.
        let root = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = root as? [String: Any],
              let response = dict["subsonic-response"] as? [String: Any],
              let playlist = response["playlist"] as? [String: Any],
              let entries = playlist["entry"] as? [[String: Any]] else { return }

        var offset = 0
        while offset < entries.count {
            try Task.checkCancellation()
            let slice = Array(entries[offset..<min(offset + chunkSize, entries.count)])
            let sliceData = try JSONSerialization.data(withJSONObject: slice, options: [])
            let songs = try JSONDecoder().decode([SubsonicSong].self, from: sliceData)
            try emit(songs)
            offset += slice.count
            await Task.yield()
        }
    }

    @discardableResult
    func createPlaylist(name: String, songIds: [String] = []) async throws -> PlaylistDetail {
        var params = [URLQueryItem(name: "name", value: name)]
        songIds.forEach { params.append(URLQueryItem(name: "songId", value: $0)) }
        guard let playlist = try await requestEnvelope(endpoint: "createPlaylist", params: params).playlist else {
            throw SubsonicError.server(code: 0, message: "Playlist was not returned")
        }
        return playlist
    }

    func updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                        isPublic: Bool? = nil, addSongIds: [String] = [],
                        removeIndexes: [Int] = []) async throws {
        var params = [URLQueryItem(name: "playlistId", value: id)]
        if let name { params.append(URLQueryItem(name: "name", value: name)) }
        if let comment { params.append(URLQueryItem(name: "comment", value: comment)) }
        if let isPublic { params.append(URLQueryItem(name: "public", value: isPublic ? "true" : "false")) }
        addSongIds.forEach { params.append(URLQueryItem(name: "songIdToAdd", value: $0)) }
        removeIndexes.forEach { params.append(URLQueryItem(name: "songIndexToRemove", value: String($0))) }
        _ = try await requestEnvelope(endpoint: "updatePlaylist", params: params)
    }

    func deletePlaylist(id: String) async throws {
        let params = [URLQueryItem(name: "id", value: id)]
        _ = try await requestEnvelope(endpoint: "deletePlaylist", params: params)
    }

    // MARK: Native REST API — playlist cover upload

    /// Uploads a custom playlist cover via Navidrome's native REST API
    /// (`POST /api/playlist/{id}/image`, multipart field `image`). This route
    /// is not part of the Subsonic API, so it authenticates with the same
    /// account via a short-lived JWT obtained from `POST /auth/login`.
    /// The server requires `EnableArtworkUpload` (default on) unless the user
    /// is an admin.
    func uploadPlaylistCover(playlistId: String, imageData: Data) async throws {
        let token = try await nativeLoginToken()
        let path = "api/playlist/\(playlistId)/image"
        let url = config.baseURL.appendingPathComponent(path)

        let boundary = "KlopydromeBoundary\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"cover.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "X-ND-Authorization")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw SubsonicError.http(status: http.statusCode)
            }
        }
        _ = data
    }

    /// Logs in to Navidrome's native API and returns the JWT used for the
    /// `X-ND-Authorization` header.
    private func nativeLoginToken() async throws -> String {
        let url = config.baseURL.appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["username": config.username, "password": config.password]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw SubsonicError.http(status: http.statusCode)
            }
        }
        struct LoginResponse: Decodable { let token: String }
        guard let login = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
            throw SubsonicError.server(code: 0, message: "Native API login failed")
        }
        return login.token
    }

    // MARK: Lyrics

    /// OpenSubsonic endpoint; returns potentially synced lyric blocks. The
    /// `enhanced=true` parameter makes the server attach word-level `cueLine`
    /// blocks (karaoke) — without it the word timing is dropped from the
    /// response (Navidrome defaults `enhanced=false`).
    func getLyricsBySongId(id: String) async throws -> [LyricsEntry] {
        let params = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "enhanced", value: "true")
        ]
        let list = try await requestEnvelope(endpoint: "getLyricsBySongId", params: params).lyricsList
        // Navidrome returns synced lyrics as `structuredLyrics` (preferred), but
        // some servers still use the legacy `lyrics` array. Prefer synced entries.
        let entries = list?.structuredLyrics ?? list?.lyrics ?? []
        return entries
    }

    /// Classic endpoint keyed by artist/title; returns plain text lyrics.
    func getLyrics(artist: String, title: String) async throws -> LyricsResult? {
        let params = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ]
        return try await requestEnvelope(endpoint: "getLyrics", params: params).lyrics
    }

    // MARK: Play queue

    func savePlayQueue(songIds: [String], currentId: String? = nil, position: Double? = nil) async throws {
        var params: [URLQueryItem] = songIds.map { URLQueryItem(name: "id", value: $0) }
        if let currentId { params.append(URLQueryItem(name: "current", value: currentId)) }
        if let position { params.append(URLQueryItem(name: "position", value: String(Int(position)))) }
        _ = try await requestEnvelope(endpoint: "savePlayQueue", params: params)
    }

    func getPlayQueue() async throws -> PlayQueuePayload? {
        try await requestEnvelope(endpoint: "getPlayQueue").playQueue
    }

    // MARK: Binary URLs (cover art, stream, download)

    func coverArtURL(id: String, size: Int? = nil) -> URL? {
        var params = [URLQueryItem(name: "id", value: id)]
        if let size { params.append(URLQueryItem(name: "size", value: String(size))) }
        return try? buildURL(endpoint: "getCoverArt", params: params, json: false)
    }

    func streamURL(songId: String, maxBitRate: Int = 0, format: String? = nil,
                   estimateContentLength: Bool = true) -> URL? {
        var params = [URLQueryItem(name: "id", value: songId)]
        if maxBitRate > 0 {
            params.append(URLQueryItem(name: "maxBitRate", value: String(maxBitRate)))
        }
        if let format {
            params.append(URLQueryItem(name: "format", value: format))
        }
        if estimateContentLength {
            params.append(URLQueryItem(name: "estimateContentLength", value: "true"))
        }
        return try? buildURL(endpoint: "stream", params: params, json: false)
    }

    func downloadURL(songId: String, maxBitRate: Int = 0, format: String? = nil) -> URL? {
        var params = [URLQueryItem(name: "id", value: songId)]
        if maxBitRate > 0 {
            params.append(URLQueryItem(name: "maxBitRate", value: String(maxBitRate)))
        }
        if let format {
            params.append(URLQueryItem(name: "format", value: format))
        }
        return try? buildURL(endpoint: "download", params: params, json: false)
    }

    // MARK: Info (require external integrations)

    func getAlbumInfo2(id: String) async throws -> AlbumInfoPayload? {
        let params = [URLQueryItem(name: "id", value: id)]
        // Note: the getAlbumInfo2 response nests its payload under the
        // `albumInfo` element (OpenSubsonic), not `albumInfo2`.
        return try await requestEnvelope(endpoint: "getAlbumInfo2", params: params).albumInfo
    }
}

public enum AlbumListType: String, CaseIterable {
    case random
    case newest
    case highest
    case frequent
    case recent
    case starred
    case alphabeticalByName
    case alphabeticalByArtist
    case byYear
    case byGenre
}