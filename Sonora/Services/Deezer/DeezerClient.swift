import Foundation

nonisolated struct DeezerStream: Sendable {
    let url: URL
    let trackID: String
    let format: String
    let key: [UInt8]
    let duration: TimeInterval?

    var contentType: String {
        format == "FLAC" ? "org.xiph.flac" : "public.mp3"
    }
}

struct DeezerLibrary: Sendable {
    var albums: [Album]
    var artists: [SavedArtist]
    var playlists: [Playlist]
    var favorites: [Track]
}

struct DeezerHome: Sendable {
    var quickPicks: [Track] = []
    var shelves: [YouTubeShelf] = []
}

/// Deezer client backed by the web gateway (`gw-light.php`) and public REST API (`api.deezer.com`).
final class DeezerClient {
    let arl: String

    private struct SessionState {
        var sid: String
        var userID: String
        var displayName: String
        var apiToken: String
        var licenseToken: String
        var secret: [UInt8]
    }

    private let http: URLSession
    private var sessionState: SessionState?
    private var connectTask: Task<SessionState, Error>?
    private var nextPublicSlot: ContinuousClock.Instant = .now

    private let gatewayURL = "https://www.deezer.com/ajax/gw-light.php"
    private let publicBase = "https://api.deezer.com"
    private let mediaURL = URL(string: "https://media.deezer.com/v1/get_url")!
    private let formats = ["MP3_320", "MP3_128", "FLAC"]
    private let uploadFormat = "MP3_MISC"

    init(arl: String) {
        self.arl = arl
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpMaximumConnectionsPerHost = 6
        self.http = URLSession(configuration: config)
    }

    // MARK: - Connection & Handshake

    private func ensureConnected() async throws -> SessionState {
        if let sessionState { return sessionState }
        if let connectTask { return try await connectTask.value }
        let task = Task { [self] () throws -> SessionState in
            defer { self.connectTask = nil }
            let sid = try await ping()
            let state = try await fetchUserData(sid: sid)
            let secret = await DeezerDecrypt.fetchSecret(session: self.http)
            let complete = SessionState(
                sid: sid,
                userID: state.userID,
                displayName: state.displayName,
                apiToken: state.apiToken,
                licenseToken: state.licenseToken,
                secret: secret
            )
            self.sessionState = complete
            return complete
        }
        connectTask = task
        return try await task.value
    }

    private func ping() async throws -> String {
        let url = URL(string: "\(gatewayURL)?method=deezer.ping&input=3&api_version=1.0&api_token=")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("arl=\(arl)", forHTTPHeaderField: "Cookie")
        let (data, _) = try await http.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [String: Any] else {
            throw DeezerError.badResponse
        }
        return textValue(results, keys: ["SESSION"]) ?? ""
    }

    private func fetchUserData(sid: String) async throws -> (userID: String, displayName: String, apiToken: String, licenseToken: String) {
        let results = try await gwRaw(method: "deezer.getUserData", apiToken: "", sid: sid, body: [:])
        guard let user = results["USER"] as? [String: Any],
              let userID = idValue(user["USER_ID"]), !userID.isEmpty, userID != "0" else {
            throw DeezerError.refused(String(localized: "Deezer refused that ARL cookie. Please sign in again."))
        }
        let options = user["OPTIONS"] as? [String: Any] ?? [:]
        let displayName = textValue(user, keys: ["BLOG_NAME"]) ?? "Deezer"
        let apiToken = textValue(results, keys: ["checkForm"]) ?? ""
        let licenseToken = textValue(options, keys: ["license_token"]) ?? ""
        return (userID, displayName, apiToken, licenseToken)
    }

    private func gateway(_ method: String, body: [String: Any]) async throws -> [String: Any] {
        let state = try await ensureConnected()
        do {
            return try await gwRaw(method: method, apiToken: state.apiToken, sid: state.sid, body: body)
        } catch {
            let refreshed = try await fetchUserData(sid: state.sid)
            let updated = SessionState(
                sid: state.sid,
                userID: refreshed.userID,
                displayName: refreshed.displayName,
                apiToken: refreshed.apiToken,
                licenseToken: refreshed.licenseToken,
                secret: state.secret
            )
            sessionState = updated
            return try await gwRaw(method: method, apiToken: updated.apiToken, sid: updated.sid, body: body)
        }
    }

    private func gwRaw(method: String, apiToken: String, sid: String, body: [String: Any]) async throws -> [String: Any] {
        let encodedMethod = method.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? method
        let encodedToken = apiToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiToken
        let cid = UInt32.random(in: 100_000_000...999_999_999)
        guard let url = URL(string: "\(gatewayURL)?method=\(encodedMethod)&input=3&api_version=1.0&api_token=\(encodedToken)&cid=\(cid)") else {
            throw DeezerError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("arl=\(arl); sid=\(sid)", forHTTPHeaderField: "Cookie")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await http.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeezerError.badResponse
        }
        if let errObj = root["error"] as? [String: Any], !errObj.isEmpty {
            throw DeezerError.refused(errObj.values.first.map { String(describing: $0) } ?? String(localized: "Deezer refused the request."))
        }
        if let errList = root["error"] as? [Any], !errList.isEmpty {
            throw DeezerError.refused(String(describing: errList[0]))
        }
        if let results = root["results"] as? [String: Any] {
            return results
        }
        if let results = root["results"] {
            return ["value": results]
        }
        return [:]
    }

    private func publicGet(_ path: String) async throws -> [String: Any] {
        var attempt = 0
        while true {
            let now = ContinuousClock.now
            let slot = max(nextPublicSlot, now)
            nextPublicSlot = slot + .milliseconds(110)
            if slot > now {
                try await Task.sleep(until: slot)
            }
            guard let url = URL(string: "\(publicBase)\(path)") else {
                throw DeezerError.badResponse
            }
            let (data, response) = try await http.data(for: URLRequest(url: url, timeoutInterval: 20))
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                guard attempt < 3 else { throw DeezerError.refused(String(localized: "Deezer API rate limit reached.")) }
                attempt += 1
                nextPublicSlot = .now + .seconds(1 << attempt)
                continue
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw DeezerError.badResponse
            }
            if let error = root["error"] as? [String: Any] {
                let code = numberValue(error, keys: ["code"]) ?? 0
                if (code == 4 || code == 700), attempt < 3 {
                    attempt += 1
                    nextPublicSlot = .now + .seconds(1 << attempt)
                    continue
                }
                let message = textValue(error, keys: ["message"]) ?? String(localized: "Deezer API error (\(code)).")
                throw DeezerError.refused(message)
            }
            return root
        }
    }

    // MARK: - Playback & Streams

    func resolveStream(for trackID: String) async throws -> DeezerStream {
        let state = try await ensureConnected()
        let raw = try await gateway("song.getData", body: ["SNG_ID": trackID])
        let data = (raw["FALLBACK"] as? [String: Any]) ?? raw
        guard let effectiveID = idValue(data["SNG_ID"]),
              let token = textValue(data, keys: ["TRACK_TOKEN"]), !token.isEmpty else {
            throw DeezerError.unplayable
        }
        let duration = numberValue(data, keys: ["DURATION"]).map(TimeInterval.init)
        let candidates = effectiveID.hasPrefix("-") ? [uploadFormat] : formats
        for format in candidates {
            if let url = try await requestStreamURL(license: state.licenseToken, trackToken: token, format: format) {
                let key = DeezerDecrypt.trackKey(trackID: effectiveID, secret: state.secret)
                return DeezerStream(url: url, trackID: effectiveID, format: format, key: key, duration: duration)
            }
        }
        throw DeezerError.unplayable
    }

    private func requestStreamURL(license: String, trackToken: String, format: String) async throws -> URL? {
        var request = URLRequest(url: mediaURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "license_token": license,
            "media": [["type": "FULL", "formats": [["cipher": "BF_CBC_STRIPE", "format": format]]]],
            "track_tokens": [trackToken],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await http.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]],
              let entry = entries.first else {
            return nil
        }
        if let errors = entry["errors"] as? [[String: Any]], !errors.isEmpty {
            return nil
        }
        guard let media = entry["media"] as? [[String: Any]],
              let sources = media.first?["sources"] as? [[String: Any]],
              let urlText = sources.first?["url"] as? String else {
            return nil
        }
        return URL(string: urlText)
    }

    // MARK: - Home & Library

    func library() async throws -> DeezerLibrary {
        let state = try await ensureConnected()
        async let albumsTask = savedAlbums(userID: state.userID)
        async let artistsTask = savedArtists(userID: state.userID)
        async let playlistsTask = savedPlaylists(userID: state.userID)
        async let favoritesTask = favoriteTracks(userID: state.userID)

        return try await DeezerLibrary(
            albums: albumsTask,
            artists: artistsTask,
            playlists: playlistsTask,
            favorites: (try? favoritesTask) ?? []
        )
    }

    func home() async throws -> DeezerHome {
        let state = try await ensureConnected()
        async let flowTask = flowTracks(userID: state.userID)
        async let libTask = library()

        let flow = (try? await flowTask) ?? []
        let lib = try await libTask
        let quickPicks = flow.isEmpty ? Array(lib.favorites.prefix(8)) : Array(flow.prefix(8))

        var shelves: [YouTubeShelf] = []
        if !lib.favorites.isEmpty {
            shelves.append(YouTubeShelf(
                title: String(localized: "Deezer favorites"),
                items: lib.favorites.prefix(20).map(YouTubeItem.track)
            ))
        }
        if !lib.albums.isEmpty {
            shelves.append(YouTubeShelf(
                title: String(localized: "Deezer albums"),
                items: lib.albums.prefix(20).map(YouTubeItem.deezerAlbum)
            ))
        }
        if !lib.playlists.isEmpty {
            shelves.append(YouTubeShelf(
                title: String(localized: "Deezer playlists"),
                items: lib.playlists.prefix(20).map(YouTubeItem.deezerPlaylist)
            ))
        }
        return DeezerHome(quickPicks: quickPicks, shelves: shelves)
    }

    private func savedAlbums(userID: String) async throws -> [Album] {
        try await profileTab("albums", userID: userID).compactMap(parseAlbum)
    }

    private func savedArtists(userID: String) async throws -> [SavedArtist] {
        try await profileTab("artists", userID: userID).compactMap(parseSavedArtist)
    }

    private func savedPlaylists(userID: String) async throws -> [Playlist] {
        try await profileTab("playlists", userID: userID).compactMap(parsePlaylist)
    }

    private func profileTab(_ tab: String, userID: String) async throws -> [[String: Any]] {
        let results = try await gateway("deezer.pageProfile", body: ["user_id": userID, "tab": tab, "nb": 200])
        guard let tabs = results["TAB"] as? [String: Any],
              let section = tabs[tab] as? [String: Any],
              let data = section["data"] as? [[String: Any]] else {
            return []
        }
        return data
    }

    private func favoriteTracks(userID: String) async throws -> [Track] {
        let results = try await gateway("favorite_song.getList", body: ["user_id": userID, "start": 0, "nb": 200])
        return parseTrackList(results)
    }

    private func flowTracks(userID: String) async throws -> [Track] {
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        let root = try await publicGet("/user/\(encoded)/flow")
        return parseTrackList(root)
    }

    // MARK: - Browse & Search

    func searchSongs(_ query: String) async throws -> [Track] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let root = try await publicGet("/search?q=\(encoded)&limit=30")
        return parseTrackList(root)
    }

    func searchAlbums(_ query: String) async throws -> [Album] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let root = try await publicGet("/search/album?q=\(encoded)&limit=25")
        let list = root["data"] as? [[String: Any]] ?? []
        return list.compactMap(parseAlbum)
    }

    func searchArtists(_ query: String) async throws -> [SavedArtist] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let root = try await publicGet("/search/artist?q=\(encoded)&limit=25")
        let list = root["data"] as? [[String: Any]] ?? []
        return list.compactMap(parseSavedArtist)
    }

    func searchPlaylists(_ query: String) async throws -> [Playlist] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let root = try await publicGet("/search/playlist?q=\(encoded)&limit=25")
        let list = root["data"] as? [[String: Any]] ?? []
        return list.compactMap(parsePlaylist)
    }

    func albumTracks(_ albumID: String) async throws -> [Track] {
        let encoded = albumID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? albumID
        let root = try await publicGet("/album/\(encoded)")
        let albumArt = coverURL(root, size: 500)
        let albumTitle = textValue(root, keys: ["title", "ALB_TITLE"]) ?? ""
        let tracksNode = root["tracks"] as? [String: Any] ?? [:]
        return parseTrackList(tracksNode).map { track in
            var copy = track
            if copy.artworkURL == nil { copy.artworkURL = albumArt }
            if copy.album.isEmpty { copy.album = albumTitle }
            if copy.albumID == nil { copy.albumID = albumID }
            return copy
        }
    }

    func playlistTracks(_ playlistID: String) async throws -> [Track] {
        _ = try await ensureConnected()
        let results = try await gateway("deezer.pagePlaylist", body: [
            "playlist_id": playlistID,
            "start": 0,
            "nb": 500,
            "lang": "en",
            "tab": 0,
            "tags": true,
            "header": true,
        ])
        let songs = results["SONGS"] as? [String: Any] ?? [:]
        return parseTrackList(songs)
    }

    func artist(_ artistID: String) async throws -> YouTubeArtist {
        let encoded = artistID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artistID
        let detail = try await publicGet("/artist/\(encoded)")
        let top = (try? await publicGet("/artist/\(encoded)/top?limit=25")) ?? [:]
        let albumsRoot = (try? await publicGet("/artist/\(encoded)/albums?limit=100")) ?? [:]

        let name = textValue(detail, keys: ["name"]) ?? ""
        let artText = textValue(detail, keys: ["picture_xl", "picture_big"])
        let artURL = artText.flatMap(URL.init(string:))
        let fans = numberValue(detail, keys: ["nb_fan"]).map { "\($0.formatted()) fans" }

        let allAlbums = (albumsRoot["data"] as? [[String: Any]] ?? []).compactMap { raw -> Album? in
            guard var parsed = parseAlbum(raw) else { return nil }
            if parsed.artists.isEmpty { parsed.artists = name }
            return parsed
        }
        return YouTubeArtist(
            id: artistID,
            name: name,
            description: nil,
            subscribers: fans,
            artworkURL: artURL,
            topTracks: parseTrackList(top),
            albums: allAlbums,
            singles: []
        )
    }

    // MARK: - Actions & Radio

    func radio(for trackID: String) async throws -> [Track] {
        _ = try await ensureConnected()
        let results = try await gateway("song.getSearchTrackMix", body: ["SNG_ID": trackID, "start": 0, "nb": 25])
        return parseTrackList(results)
    }

    func setTrackSaved(_ trackID: String, saved: Bool) async throws {
        _ = try await gateway(saved ? "favorite_song.add" : "favorite_song.remove", body: ["SNG_ID": trackID])
    }

    func add(_ trackID: String, toPlaylist playlistID: String) async throws {
        _ = try await gateway("playlist.addSongs", body: ["playlist_id": playlistID, "songs": [[trackID, 0]]])
    }

    // MARK: - Wire Parsers

    private func parseTrackList(_ container: [String: Any]) -> [Track] {
        let list = container["data"] as? [[String: Any]] ?? []
        return list.compactMap(parseTrack)
    }

    private func parseTrack(_ raw: [String: Any]) -> Track? {
        guard let trackID = idValue(raw["SNG_ID"] ?? raw["id"]) else { return nil }
        let baseTitle = textValue(raw, keys: ["SNG_TITLE", "title", "TITLE"]) ?? ""
        let version = textValue(raw, keys: ["VERSION"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = (!version.isEmpty && !baseTitle.contains(version)) ? "\(baseTitle) \(version)" : baseTitle

        let (artists, artistRefs) = parseArtists(raw)
        let albumNode = raw["album"] as? [String: Any]
        let albumName = albumNode.flatMap { textValue($0, keys: ["title"]) } ?? textValue(raw, keys: ["ALB_TITLE"]) ?? ""
        let albumID = idValue(albumNode?["id"] ?? raw["ALB_ID"])
        let artwork = albumNode.flatMap { coverURL($0, size: 500) } ?? coverURL(raw, size: 500)
        let duration = TimeInterval(numberValue(raw, keys: ["DURATION", "duration"]) ?? 0)

        return Track(
            title: title,
            artists: artists,
            artistReferences: artistRefs,
            album: albumName,
            albumID: albumID,
            artworkURL: artwork,
            duration: duration,
            source: .deezer(trackID)
        )
    }

    private func parseAlbum(_ raw: [String: Any]) -> Album? {
        guard let albumID = idValue(raw["ALB_ID"] ?? raw["id"]) else { return nil }
        let (artists, _) = parseArtists(raw)
        let release = textValue(raw, keys: ["release_date", "PHYSICAL_RELEASE_DATE", "DIGITAL_RELEASE_DATE"]) ?? ""
        let year = release.split(separator: "-").first.flatMap { Int($0) } ?? 0
        return Album(
            id: albumID,
            title: textValue(raw, keys: ["ALB_TITLE", "title"]) ?? "",
            artists: artists,
            artworkURL: coverURL(raw, size: 500),
            year: year,
            trackCount: Int(numberValue(raw, keys: ["NB_TRAK", "nb_tracks"]) ?? 0)
        )
    }

    private func parsePlaylist(_ raw: [String: Any]) -> Playlist? {
        guard let playlistID = idValue(raw["PLAYLIST_ID"] ?? raw["id"]) else { return nil }
        let creator = (raw["creator"] as? [String: Any]) ?? (raw["user"] as? [String: Any])
        let owner = textValue(raw, keys: ["PARENT_USERNAME", "CREATOR_NAME"])
            ?? creator.flatMap { textValue($0, keys: ["name"]) }
            ?? ""
        let md5 = textValue(raw, keys: ["PLAYLIST_PICTURE", "picture"])
        let kind = textValue(raw, keys: ["PICTURE_TYPE"]) ?? "playlist"
        let artwork = imageURL(kind: kind, md5: md5, size: 500)
            ?? textValue(raw, keys: ["picture_big", "picture_medium"]).flatMap(URL.init(string:))

        return Playlist(
            id: playlistID,
            title: textValue(raw, keys: ["TITLE", "title"]) ?? "",
            owner: owner,
            artworkURL: artwork,
            trackCount: Int(numberValue(raw, keys: ["NB_SONG", "nb_tracks"]) ?? 0)
        )
    }

    private func parseSavedArtist(_ raw: [String: Any]) -> SavedArtist? {
        guard let artistID = idValue(raw["ART_ID"] ?? raw["id"]) else { return nil }
        let md5 = textValue(raw, keys: ["picture", "ART_PICTURE"])
        let artwork = imageURL(kind: "artist", md5: md5, size: 300)
            ?? textValue(raw, keys: ["picture_big", "picture_medium"]).flatMap(URL.init(string:))
        return SavedArtist(
            id: artistID,
            name: textValue(raw, keys: ["ART_NAME", "name"]) ?? "",
            artworkURL: artwork
        )
    }

    private func parseArtists(_ raw: [String: Any]) -> (String, [ArtistReference]) {
        if let contributors = raw["SNG_CONTRIBUTORS"] as? [String: Any],
           let main = contributors["mainartist"] as? [String], !main.isEmpty {
            let primaryID = idValue(raw["ART_ID"])
            let refs = main.enumerated().map { idx, name in
                ArtistReference(name: name, id: idx == 0 ? primaryID : nil)
            }
            return (main.joined(separator: ", "), refs)
        }
        if let artist = raw["artist"] as? [String: Any],
           let name = textValue(artist, keys: ["name"]), !name.isEmpty {
            return (name, [ArtistReference(name: name, id: idValue(artist["id"]))])
        }
        let name = textValue(raw, keys: ["ART_NAME", "artist_name"]) ?? ""
        let refs = name.isEmpty ? [] : [ArtistReference(name: name, id: idValue(raw["ART_ID"]))]
        return (name, refs)
    }

    private func coverURL(_ raw: [String: Any], size: Int) -> URL? {
        let md5 = textValue(raw, keys: ["md5_image", "ALB_PICTURE", "picture"])
        if let built = imageURL(kind: "cover", md5: md5, size: size) {
            return built
        }
        return textValue(raw, keys: ["cover_xl", "cover_big", "picture_big"]).flatMap(URL.init(string:))
    }

    private func imageURL(kind: String, md5: String?, size: Int) -> URL? {
        guard let md5 = md5?.trimmingCharacters(in: .whitespacesAndNewlines), !md5.isEmpty else { return nil }
        let parts = md5.split(separator: "-")
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isHexDigit) }) else {
            return nil
        }
        return URL(string: "https://cdn-images.dzcdn.net/images/\(kind)/\(md5)/\(size)x\(size)-000000-80-0-0.jpg")
    }

    private func idValue(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty, text != "0" { return text }
        if let num = value as? Int64, num != 0 { return String(num) }
        if let num = value as? Int, num != 0 { return String(num) }
        if let num = value as? NSNumber {
            let integer = num.int64Value
            return integer == 0 ? nil : String(integer)
        }
        return nil
    }

    private func textValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = dict[key] as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func numberValue(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? Int64 { return Int(value) }
            if let value = dict[key] as? NSNumber { return value.intValue }
            if let text = dict[key] as? String, let parsed = Int(text) { return parsed }
        }
        return nil
    }
}
