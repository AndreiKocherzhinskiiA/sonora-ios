import Foundation

/// A card on a home shelf, by where it leads.
enum YouTubeItem: Identifiable {
    case track(Track)
    case playlist(Playlist)
    case album(Album)
    case subsonicPlaylist(Playlist)
    case subsonicAlbum(Album)
    case deezerPlaylist(Playlist)
    case deezerAlbum(Album)

    var id: String {
        switch self {
        case .track(let track): "track-\(track.id)"
        case .playlist(let playlist): "playlist-\(playlist.id)"
        case .album(let album): "album-\(album.id)"
        case .subsonicPlaylist(let playlist): "subsonic-playlist-\(playlist.id)"
        case .subsonicAlbum(let album): "subsonic-album-\(album.id)"
        case .deezerPlaylist(let playlist): "deezer-playlist-\(playlist.id)"
        case .deezerAlbum(let album): "deezer-album-\(album.id)"
        }
    }
}

/// A titled row of cards, such as "Listen again" or "Mixed for you".
struct YouTubeShelf: Identifiable {
    let id = UUID()
    let title: String
    let items: [YouTubeItem]
}

/// The YouTube Music home page.
struct YouTubeHome {
    var listenAgain: [YouTubeItem] = []
    var quickPicks: [Track] = []
    var shelves: [YouTubeShelf] = []
}

/// An artist as a search result or a library entry.
struct SavedArtist: Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var artworkURL: URL?
}

/// An artist page: who they are, their top songs, and their releases.
struct YouTubeArtist: Sendable {
    let id: String
    var name: String
    var description: String?
    var subscribers: String?
    var artworkURL: URL?
    var topTracks: [Track]
    var albums: [Album]
    var singles: [Album]
}

/// Where a link in the app leads, so a sheet or a card can open it without owning a navigation link.
enum YouTubeDestination: Hashable {
    case artist(id: String, name: String)
    case playlist(Playlist)
    case album(Album)
    case subsonicArtist(id: String, name: String)
    case subsonicPlaylist(Playlist)
    case subsonicAlbum(Album)
    case deezerArtist(id: String, name: String)
    case deezerPlaylist(Playlist)
    case deezerAlbum(Album)
    case history
}
