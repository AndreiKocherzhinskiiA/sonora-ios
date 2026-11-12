import CryptoKit
import Foundation

/// The InnerTube clients the app speaks as, the Swift form of `ytmusic::Client`.
enum YouTubeClientKind {
    case music
    case visionOS

    var name: String {
        switch self {
        case .music: "WEB_REMIX"
        case .visionOS: "VISIONOS"
        }
    }

    var version: String {
        switch self {
        case .music: "1.20260707.12.00"
        case .visionOS: "1.02"
        }
    }

    var id: Int {
        switch self {
        case .music: 67
        case .visionOS: 101
        }
    }

    var userAgent: String {
        switch self {
        case .music:
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
        case .visionOS:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        }
    }

    var origin: String {
        switch self {
        case .music: "https://music.youtube.com"
        case .visionOS: "https://www.youtube.com"
        }
    }

    var base: String { origin + "/youtubei/v1/" }

    func context(visitor: String) -> [String: Any] {
        var client: [String: Any] = [
            "hl": "en",
            "gl": "US",
            "clientName": name,
            "clientVersion": version,
            "userAgent": userAgent,
            "utcOffsetMinutes": 0,
        ]
        if !visitor.isEmpty { client["visitorData"] = visitor }
        switch self {
        case .music:
            client.merge([
                "osName": "Windows", "osVersion": "10.0", "platform": "DESKTOP",
                "clientFormFactor": "UNKNOWN_FORM_FACTOR", "browserName": "Chrome",
                "browserVersion": "125.0.0.0", "originalUrl": "https://music.youtube.com",
            ]) { $1 }
        case .visionOS:
            client.merge([
                "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                "osName": "visionOS", "osVersion": "26.5.23O471",
            ]) { $1 }
        }
        return [
            "client": client,
            "user": ["enableSafetyMode": false, "lockedSafetyMode": false],
            "request": ["useSsl": true, "internalExperimentFlags": [String]()],
        ]
    }
}

/// A stream the host serves for one track, chosen from the player response.
struct YouTubeStream: Sendable {
    let url: URL
    let userAgent: String
    let duration: TimeInterval?
    let contentLength: Int64?
}

enum YouTubeError: LocalizedError {
    case signedOut
    case http(String, Int)
    case notJSON(String)
    case api(String)
    case unplayable(String)
    case needsSignedStream
    case refused

    var errorDescription: String? {
        switch self {
        case .signedOut: String(localized: "Sign in to YouTube Music first.")
        case .http(let endpoint, let status): "\(endpoint) failed with status \(status)"
        case .notJSON(let endpoint): "\(endpoint) returned a response that is not JSON"
        case .api(let message): message
        case .unplayable(let reason): reason
        case .needsSignedStream:
            String(localized: "YouTube only serves this song to the signed-in player, which is not on iPhone yet.")
        case .refused: String(localized: "The stream host refused the song.")
        }
    }
}

/// The YouTube Music API, the Swift form of the desktop `ytmusic` client: signed-in search and the
/// guest `VISIONOS` stream, whose urls need no deciphering and no proof-of-origin token.
final class YouTubeClient {
    private let session: URLSession
    private var cookies: String
    private var visitor: String?

    /// `cookies` is the value of a `Cookie` header from a signed-in browser.
    init(cookies: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
        self.cookies = cookies
    }

    // MARK: Search

    private static let songsFilter = "EgWKAQIIAQ%3D%3D"

    func searchSongs(_ query: String) async throws -> [Track] {
        let response = try await execute(
            "search", client: .music, payload: ["query": query, "params": Self.songsFilter]
        )
        return YouTubeParser.songs(in: response)
    }

    // MARK: Browse

    /// How many lots of home shelves are followed, as the desktop does.
    private static let homePages = 6
    private static let maxPages = 50
    static let likedSongs = "LM"

    /// The home page: Listen again, Quick picks and the shelves behind them, following the
    /// continuation chain. A lot that fails ends the feed with what came before it.
    func home(onPage: (@MainActor (YouTubeHome) -> Void)? = nil) async throws -> YouTubeHome {
        var response = try await execute("browse", client: .music, payload: ["browseId": "FEmusic_home"])
        var home = YouTubeHome()
        Self.gather(YouTubeParser.shelves(in: response), into: &home)
        onPage?(home)
        for _ in 1..<Self.homePages {
            guard let token = YouTubeParser.continuation(in: response) else { break }
            try Task.checkCancellation()
            response = try await execute("browse", client: .music, payload: ["continuation": token])
            Self.gather(YouTubeParser.shelves(in: response), into: &home)
            onPage?(home)
        }
        return home
    }

    private static func gather(_ shelves: [YouTubeShelf], into home: inout YouTubeHome) {
        for shelf in shelves {
            switch shelf.title {
            case "Listen again":
                home.listenAgain = shelf.items
            case "Quick picks":
                home.quickPicks = shelf.items.compactMap {
                    if case .track(let track) = $0 { track } else { nil }
                }
                .prefix(15).map { $0 }
            case "Music videos for you":
                break
            default:
                if !shelf.items.isEmpty { home.shelves.append(shelf) }
            }
        }
    }

    /// The playlists saved to the library.
    func libraryPlaylists() async throws -> [Playlist] {
        let response = try await execute("browse", client: .music, payload: ["browseId": "FEmusic_liked_playlists"])
        return YouTubeParser.libraryPlaylists(in: response)
    }

    /// Every song of a playlist, following its pages.
    func playlistTracks(_ id: String) async throws -> [Track] {
        let browse = id.hasPrefix("VL") ? id : "VL\(id)"
        var response = try await execute("browse", client: .music, payload: ["browseId": browse])
        var tracks = YouTubeParser.listTracks(in: response)
        var pages = 0
        while let token = YouTubeParser.nextPage(in: response), pages < Self.maxPages {
            pages += 1
            response = try await execute("browse", client: .music, payload: ["continuation": token])
            tracks += YouTubeParser.listTracks(in: response)
        }
        return tracks
    }

    /// The songs of an album, whose page holds them all at once.
    func albumTracks(_ browseID: String) async throws -> [Track] {
        let response = try await execute("browse", client: .music, payload: ["browseId": browseID])
        return YouTubeParser.listTracks(in: response)
    }

    // MARK: Artists, albums, search filters and radio

    private static let albumsFilter = "EgWKAQIYAQ%3D%3D"
    private static let artistsFilter = "EgWKAQIgAQ%3D%3D"
    private static let playlistsFilter = "EgWKAQIoAQ%3D%3D"

    func searchAlbums(_ query: String) async throws -> [Album] {
        YouTubeParser.searchAlbums(in: try await execute("search", client: .music, payload: ["query": query, "params": Self.albumsFilter]))
    }

    func searchArtists(_ query: String) async throws -> [SavedArtist] {
        YouTubeParser.searchArtists(in: try await execute("search", client: .music, payload: ["query": query, "params": Self.artistsFilter]))
    }

    func searchPlaylists(_ query: String) async throws -> [Playlist] {
        YouTubeParser.searchPlaylists(in: try await execute("search", client: .music, payload: ["query": query, "params": Self.playlistsFilter]))
    }

    func artist(_ id: String) async throws -> YouTubeArtist {
        let response = try await execute("browse", client: .music, payload: ["browseId": id])
        guard let artist = YouTubeParser.artist(in: response, id: id) else {
            throw YouTubeError.api("The artist page has no header.")
        }
        return artist
    }

    func libraryAlbums() async throws -> [Album] {
        YouTubeParser.libraryAlbums(in: try await execute("browse", client: .music, payload: ["browseId": "FEmusic_liked_albums"]))
    }

    func savedArtists() async throws -> [SavedArtist] {
        YouTubeParser.artists(in: try await execute("browse", client: .music, payload: ["browseId": "FEmusic_library_corpus_artists"]))
    }

    /// A song's station: the song first, then what YouTube's automix picks after it. Pass the
    /// returned token back to get the next stretch.
    func radio(for videoID: String, continuation: String? = nil) async throws -> (tracks: [Track], next: String?) {
        var payload: [String: Any] = [
            "videoId": videoID,
            "playlistId": "RDAMVM\(videoID)",
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
        ]
        if let continuation { payload["continuation"] = continuation }
        let response = try await execute("next", client: .music, payload: payload)
        return YouTubeParser.radio(in: response, continued: continuation != nil)
    }

    /// Subscribes to or leaves an artist, which saves it to or removes it from the library.
    func setSaved(artist id: String, saved: Bool) async throws {
        let page = try await execute("browse", client: .music, payload: ["browseId": id])
        guard let channel = page.find("subscribeButtonRenderer").first?["channelId"].string else {
            throw YouTubeError.api("The artist page has no subscription channel.")
        }
        _ = try await execute(
            saved ? "subscription/subscribe" : "subscription/unsubscribe",
            client: .music, payload: ["channelIds": [channel]]
        )
    }

    /// Saves an album to or removes it from the library, through its audio playlist.
    func setSaved(playlist id: String, saved: Bool) async throws {
        _ = try await execute(saved ? "like/like" : "like/removelike", client: .music, payload: ["target": ["playlistId": id]])
    }

    // MARK: Mutations and lyrics

    /// Likes or unlikes a song, which adds it to or takes it out of Liked music.
    func rate(_ videoID: String, liked: Bool) async throws {
        _ = try await execute(liked ? "like/like" : "like/removelike", client: .music, payload: ["target": ["videoId": videoID]])
    }

    /// Adds a song to one of the account's playlists.
    func add(_ videoID: String, toPlaylist playlistID: String) async throws {
        _ = try await execute("browse/edit_playlist", client: .music, payload: [
            "playlistId": playlistID.hasPrefix("VL") ? String(playlistID.dropFirst(2)) : playlistID,
            "actions": [[
                "action": "ACTION_ADD_VIDEO",
                "addedVideoId": videoID,
                "dedupeOption": "DEDUPE_OPTION_SKIP",
            ]],
        ])
    }

    /// The plain lyrics YouTube Music keeps for a song, or nil when it has none.
    func lyrics(for videoID: String) async throws -> String? {
        let next = try await execute("next", client: .music, payload: [
            "videoId": videoID,
            "playlistId": "RDAMVM\(videoID)",
            "enablePersistentPlaylistPanel": true,
        ])
        let browse = next.find("browseEndpoint").compactMap { endpoint -> String? in
            let kind = endpoint.at(
                "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"
            ).string
            guard let id = endpoint["browseId"].string else { return nil }
            return kind == "MUSIC_PAGE_TYPE_TRACK_LYRICS" || id.hasPrefix("MPLYt") ? id : nil
        }.first
        guard let browse else { return nil }
        let response = try await execute("browse", client: .music, payload: ["browseId": browse])
        return response.find("musicDescriptionShelfRenderer")
            .compactMap { $0["description"].runText }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Playback

    /// Resolves an audio stream. AVPlayer validates the media response during playback, avoiding
    /// a separate range request that some hosts answer with the entire audio file.
    func stream(for videoID: String) async throws -> YouTubeStream {
        let response = try await guestPlayer(videoID)
        let playability = response["playabilityStatus"]
        guard playability["status"].string == "OK" else {
            if playability["status"].string == "LOGIN_REQUIRED" { throw YouTubeError.needsSignedStream }
            let reason = playability["reason"].string ?? playability["status"].string ?? "unknown"
            throw YouTubeError.unplayable("\(videoID) is not playable: \(reason)")
        }
        let formats = response.at("streamingData", "adaptiveFormats").array.compactMap { format -> (JSON, URL)? in
            guard format["mimeType"].string?.hasPrefix("audio/") == true,
                  let text = format["url"].string, let url = URL(string: text) else { return nil }
            return (format, url)
        }
        let aac = formats.filter { $0.0["mimeType"].string?.hasPrefix("audio/mp4") == true }
        let pool = aac.isEmpty ? formats : aac
        guard let best = pool.max(by: { ($0.0["bitrate"].int ?? 0) < ($1.0["bitrate"].int ?? 0) }) else {
            throw YouTubeError.needsSignedStream
        }
        let stream = YouTubeStream(
            url: best.1,
            userAgent: YouTubeClientKind.visionOS.userAgent,
            duration: best.0["approxDurationMs"].double.map { $0 / 1000 },
            contentLength: best.0["contentLength"].string.flatMap(Int64.init)
        )
        return stream
    }

    private func guestPlayer(_ videoID: String) async throws -> JSON {
        let first = try await guestRequest(videoID, visitor: nil)
        guard first.at("playabilityStatus", "status").string == "LOGIN_REQUIRED",
              let issued = first.at("responseContext", "visitorData").string else { return first }
        // The visitor was refused, so a fresh one the server issued is adopted and tried once.
        visitor = issued
        return try await guestRequest(videoID, visitor: issued)
    }

    private func guestRequest(_ videoID: String, visitor override: String?) async throws -> JSON {
        let payload: [String: Any] = [
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "cpn": Self.randomString(16),
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
        ]
        return try await execute("player", client: .visionOS, payload: payload, signedIn: false, visitor: override)
    }

    // MARK: Transport

    private func execute(
        _ endpoint: String,
        client: YouTubeClientKind,
        payload: [String: Any],
        signedIn: Bool = true,
        visitor override: String? = nil
    ) async throws -> JSON {
        let visitorID: String
        switch (signedIn, override) {
        case (true, _): visitorID = ""
        case (false, let issued?): visitorID = issued
        case (false, nil): visitorID = await currentVisitor()
        }

        var body = payload
        body["context"] = client.context(visitor: visitorID)
        if client == .music { body["isAudioOnly"] = true }

        var request = URLRequest(url: URL(string: "\(client.base)\(endpoint)?prettyPrint=false&alt=json")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.origin, forHTTPHeaderField: "Origin")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(String(client.id), forHTTPHeaderField: "X-Youtube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-Youtube-Client-Version")
        switch signedIn {
        case true:
            guard let sapisid = Self.sapisid(in: cookies) else { throw YouTubeError.signedOut }
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            request.setValue(Self.authorization(sapisid: sapisid, origin: client.origin), forHTTPHeaderField: "Authorization")
            request.setValue(client.origin, forHTTPHeaderField: "X-Origin")
            request.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        case false:
            request.setValue(visitorID, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSON(data: data), json.exists else { throw YouTubeError.notJSON(endpoint) }
        if let message = json.at("error", "message").string {
            throw YouTubeError.api("\(endpoint) failed (\(status)): \(message)")
        }
        guard (200..<300).contains(status) else { throw YouTubeError.http(endpoint, status) }
        return json
    }

    /// A server-issued visitor id for guest requests, fetched once.
    private func currentVisitor() async -> String {
        if let visitor { return visitor }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/sw.js_data")!)
        request.setValue(YouTubeClientKind.visionOS.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let text = String(data: data, encoding: .utf8),
              let range = text.range(of: #""(Cg[A-Za-z0-9%_+=-]{20,})""#, options: .regularExpression) else {
            return ""
        }
        let issued = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        visitor = issued
        return issued
    }

    // MARK: Helpers

    /// The `SAPISID` value of a cookie header, falling back to the secure variant.
    static func sapisid(in header: String) -> String? {
        let pairs = header.split(separator: ";").compactMap { pair -> (String, String)? in
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
        for name in ["SAPISID", "__Secure-3PAPISID"] {
            if let found = pairs.first(where: { $0.0 == name }) { return found.1 }
        }
        return nil
    }

    private static func authorization(sapisid: String, origin: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let digest = Insecure.SHA1.hash(data: Data("\(timestamp) \(sapisid) \(origin)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hex)"
    }

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
