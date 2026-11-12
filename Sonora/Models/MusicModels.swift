import Foundation

struct ArtistReference: Codable, Hashable, Sendable {
    let name: String
    let id: String?
}

struct Track: Codable, Hashable, Identifiable, Sendable {
    enum Source: Codable, Hashable, Sendable {
        case local(URL)
        case stream(URL)
        /// A YouTube Music video id, resolved to a stream when the track plays.
        case youtube(String)
    }

    var id: UUID
    var title: String
    var artists: String
    var artistReferences: [ArtistReference]
    var album: String
    /// The browse id of the album page, when the service gave one.
    var albumID: String?
    var artworkURL: URL?
    var duration: TimeInterval
    var explicit: Bool
    var trackNumber: Int
    var discNumber: Int
    var source: Source

    init(
        id: UUID = UUID(),
        title: String,
        artists: String = "",
        artistReferences: [ArtistReference] = [],
        album: String = "",
        albumID: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval = 0,
        explicit: Bool = false,
        trackNumber: Int = 0,
        discNumber: Int = 0,
        source: Source
    ) {
        self.id = id
        self.title = title
        self.artists = artists
        self.artistReferences = artistReferences
        self.album = album
        self.albumID = albumID
        self.artworkURL = artworkURL
        self.duration = duration
        self.explicit = explicit
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.source = source
    }

    /// The same track under a new id, so one song can sit in the queue twice and be told apart.
    init(copying other: Track) {
        self = other
        self.id = UUID()
    }

    var sourceURL: URL {
        switch source {
        case .local(let url), .stream(let url): url
        case .youtube(let id): URL(string: "https://music.youtube.com/watch?v=\(id)")!
        }
    }

    var subtitle: String {
        if !artists.isEmpty { return artists }
        if !album.isEmpty { return album }
        return String(localized: "Unknown artist")
    }
}

struct Album: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
    var artists: String
    var artworkURL: URL?
    var year: Int
    var trackCount: Int
}

struct Playlist: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
    var owner: String
    var artworkURL: URL?
    var trackCount: Int
}

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    mutating func advance() {
        self = switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

