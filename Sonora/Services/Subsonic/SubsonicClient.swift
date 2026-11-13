import Foundation

enum SubsonicError: LocalizedError {
    case invalidInput(String)
    case signedOut
    case badResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .api(let message): message
        case .signedOut: String(localized: "Sign in to a Subsonic or Navidrome server in Settings.")
        case .badResponse: String(localized: "The server returned an unexpected response.")
        }
    }
}

struct SubsonicHome: Sendable {
    var quickPicks: [Track] = []
    var shelves: [YouTubeShelf] = []
}

struct SubsonicArtist: Sendable {
    let id: String
    let name: String
    let artworkURL: URL?
    let albums: [Album]
}

/// OpenSubsonic / Navidrome REST client (`v1.16.1`, JSON responses, salted MD5 auth).
final class SubsonicClient: Sendable {
    private static let apiVersion = "1.16.1"
    private static let clientName = "sonora"

    private let serverURL: URL
    private let username: String
    private let salt: String
    private let token: String

    init(credentials: SubsonicSession.Credentials) throws {
        guard let url = URL(string: credentials.server) else {
            throw SubsonicError.invalidInput(String(localized: "Invalid server URL."))
        }
        self.serverURL = url
        self.username = credentials.username
        self.salt = credentials.salt
        self.token = credentials.token
    }

    // MARK: - Requests

    func ping() async throws {
        _ = try await call("ping")
    }

    func home() async throws -> SubsonicHome {
        async let recentTask = call("getAlbumList2", query: [
            URLQueryItem(name: "type", value: "recent"),
            URLQueryItem(name: "size", value: "12"),
        ])
        async let newestTask = call("getAlbumList2", query: [
            URLQueryItem(name: "type", value: "newest"),
            URLQueryItem(name: "size", value: "12"),
        ])
        async let randomTask = call("getRandomSongs", query: [
            URLQueryItem(name: "size", value: "12"),
        ])

        let recentAlbums = (try? await recentTask.albumList2?.album?.map(album(from:))) ?? []
        let newestAlbums = (try? await newestTask.albumList2?.album?.map(album(from:))) ?? []
        let quickPicks = (try? await randomTask.randomSongs?.song?.map(track(from:))) ?? []

        var shelves: [YouTubeShelf] = []
        if !recentAlbums.isEmpty {
            shelves.append(YouTubeShelf(
                title: String(localized: "Recently played"),
                items: recentAlbums.map(YouTubeItem.subsonicAlbum)
            ))
        }
        if !newestAlbums.isEmpty {
            shelves.append(YouTubeShelf(
                title: String(localized: "New releases"),
                items: newestAlbums.map(YouTubeItem.subsonicAlbum)
            ))
        }
        return SubsonicHome(quickPicks: quickPicks, shelves: shelves)
    }

    func library() async throws -> (albums: [Album], artists: [SavedArtist], playlists: [Playlist]) {
        async let albumsResponse = call("getAlbumList2", query: [
            URLQueryItem(name: "type", value: "alphabeticalByName"),
            URLQueryItem(name: "size", value: "100"),
        ])
        async let artistsResponse = call("getArtists")
        async let playlistsResponse = call("getPlaylists")

        let albums = try await albumsResponse.albumList2?.album?.map(album(from:)) ?? []
        let indexes = try await artistsResponse.artists?.index ?? []
        let artists = indexes
            .flatMap { $0.artist ?? [] }
            .map { SavedArtist(id: $0.id, name: $0.name, artworkURL: coverURL(for: $0.coverArt)) }
        let playlists = try await playlistsResponse.playlists?.playlist?.map(playlist(from:)) ?? []
        return (albums, artists, playlists)
    }

    func searchSongs(_ query: String) async throws -> [Track] {
        let response = try await call("search3", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "30"),
            URLQueryItem(name: "albumCount", value: "0"),
            URLQueryItem(name: "artistCount", value: "0"),
        ])
        return response.searchResult3?.song?.map(track(from:)) ?? []
    }

    func searchAlbums(_ query: String) async throws -> [Album] {
        let response = try await call("search3", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "0"),
            URLQueryItem(name: "albumCount", value: "30"),
            URLQueryItem(name: "artistCount", value: "0"),
        ])
        return response.searchResult3?.album?.map(album(from:)) ?? []
    }

    func searchArtists(_ query: String) async throws -> [SavedArtist] {
        let response = try await call("search3", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "songCount", value: "0"),
            URLQueryItem(name: "albumCount", value: "0"),
            URLQueryItem(name: "artistCount", value: "30"),
        ])
        return response.searchResult3?.artist?.map {
            SavedArtist(id: $0.id, name: $0.name, artworkURL: coverURL(for: $0.coverArt))
        } ?? []
    }

    func searchPlaylists(_ query: String) async throws -> [Playlist] {
        let response = try await call("getPlaylists")
        let all = response.playlists?.playlist?.map(playlist(from:)) ?? []
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.owner.localizedCaseInsensitiveContains(query)
        }
    }

    func albumTracks(_ id: String) async throws -> [Track] {
        let response = try await call("getAlbum", query: [URLQueryItem(name: "id", value: id)])
        return response.album?.song?.map(track(from:)) ?? []
    }

    func artist(_ id: String) async throws -> SubsonicArtist {
        let response = try await call("getArtist", query: [URLQueryItem(name: "id", value: id)])
        guard let wire = response.artist else { throw SubsonicError.badResponse }
        return SubsonicArtist(
            id: wire.id,
            name: wire.name,
            artworkURL: coverURL(for: wire.coverArt),
            albums: wire.album?.map(album(from:)) ?? []
        )
    }

    func playlistTracks(_ id: String) async throws -> [Track] {
        let response = try await call("getPlaylist", query: [URLQueryItem(name: "id", value: id)])
        return response.playlist?.entry?.map(track(from:)) ?? []
    }

    func streamURL(for id: String) -> URL? {
        restURL("stream", extra: [URLQueryItem(name: "id", value: id)])
    }

    func coverURL(for id: String?) -> URL? {
        guard let id, !id.isEmpty else { return nil }
        return restURL("getCoverArt", extra: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "size", value: "600"),
        ])
    }

    // MARK: - HTTP & Mapping

    private func restURL(_ endpoint: String, extra: [URLQueryItem] = [], json: Bool = false) -> URL? {
        var components = URLComponents(
            url: serverURL.appending(path: "rest/\(endpoint).view"),
            resolvingAgainstBaseURL: false
        )
        var items = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
        ]
        if json {
            items.append(URLQueryItem(name: "f", value: "json"))
        }
        items.append(contentsOf: extra)
        components?.queryItems = items
        return components?.url
    }

    private func call(_ endpoint: String, query: [URLQueryItem] = []) async throws -> WireBody {
        guard let url = restURL(endpoint, extra: query, json: true) else {
            throw SubsonicError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SubsonicError.badResponse
        }
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
        let body = envelope.subsonicResponse
        if body.status != "ok" {
            throw SubsonicError.api(body.error?.message ?? String(localized: "Subsonic request failed."))
        }
        return body
    }

    private func track(from song: WireSong) -> Track {
        let artistName = song.artist ?? ""
        let artistRefs = artistName.isEmpty
            ? []
            : [ArtistReference(name: artistName, id: song.artistId)]
        return Track(
            title: song.title,
            artists: artistName,
            artistReferences: artistRefs,
            album: song.album ?? "",
            albumID: song.albumId,
            artworkURL: coverURL(for: song.coverArt ?? song.albumId),
            duration: TimeInterval(song.duration ?? 0),
            trackNumber: song.track ?? 0,
            discNumber: song.discNumber ?? 0,
            source: .subsonic(song.id)
        )
    }

    private func album(from wire: WireAlbum) -> Album {
        Album(
            id: wire.id,
            title: wire.name ?? wire.title ?? "",
            artists: wire.artist ?? "",
            artworkURL: coverURL(for: wire.coverArt ?? wire.id),
            year: wire.year ?? 0,
            trackCount: wire.songCount ?? 0
        )
    }

    private func playlist(from wire: WirePlaylist) -> Playlist {
        Playlist(
            id: wire.id,
            title: wire.name,
            owner: wire.owner ?? "",
            artworkURL: coverURL(for: wire.coverArt),
            trackCount: wire.songCount ?? 0
        )
    }
}

// MARK: - Wire Models

private struct WireEnvelope: Decodable {
    let subsonicResponse: WireBody

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

private struct WireBody: Decodable {
    let status: String
    let error: WireError?
    let albumList2: WireAlbumList?
    let randomSongs: WireSongList?
    let artists: WireArtistsDirectory?
    let artist: WireArtistDetail?
    let album: WireAlbumDetail?
    let playlists: WirePlaylistList?
    let playlist: WirePlaylistDetail?
    let searchResult3: WireSearchResult?
}

private struct WireError: Decodable {
    let code: Int?
    let message: String?
}

private struct WireAlbumList: Decodable {
    let album: [WireAlbum]?
}

private struct WireSongList: Decodable {
    let song: [WireSong]?
}

private struct WireArtistsDirectory: Decodable {
    let index: [WireArtistIndex]?
}

private struct WireArtistIndex: Decodable {
    let artist: [WireArtistSummary]?
}

private struct WireArtistSummary: Decodable {
    let id: String
    let name: String
    let coverArt: String?
}

private struct WireArtistDetail: Decodable {
    let id: String
    let name: String
    let coverArt: String?
    let album: [WireAlbum]?
}

private struct WireAlbumDetail: Decodable {
    let id: String
    let song: [WireSong]?
}

private struct WirePlaylistList: Decodable {
    let playlist: [WirePlaylist]?
}

private struct WirePlaylistDetail: Decodable {
    let id: String
    let entry: [WireSong]?
}

private struct WireSearchResult: Decodable {
    let artist: [WireArtistSummary]?
    let album: [WireAlbum]?
    let song: [WireSong]?
}

private struct WireAlbum: Decodable {
    let id: String
    let name: String?
    let title: String?
    let artist: String?
    let coverArt: String?
    let songCount: Int?
    let year: Int?
}

private struct WirePlaylist: Decodable {
    let id: String
    let name: String
    let owner: String?
    let coverArt: String?
    let songCount: Int?
}

private struct WireSong: Decodable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let discNumber: Int?
}
