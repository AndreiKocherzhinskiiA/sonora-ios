import Foundation
import Observation

/// Holds the signed-in Deezer home shelves and library collections across tabs.
@Observable
final class DeezerFeed {
    private(set) var home: DeezerHome?
    private(set) var albums: [Album] = []
    private(set) var artists: [SavedArtist] = []
    private(set) var playlists: [Playlist] = []
    private(set) var favorites: [Track] = []
    private(set) var isLoading = false
    private(set) var failure: String?

    func refresh(using client: DeezerClient?) async {
        guard let client else {
            clear()
            return
        }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            async let homeTask = client.home()
            async let libraryTask = client.library()
            home = try await homeTask
            let library = try await libraryTask
            albums = library.albums
            artists = library.artists
            playlists = library.playlists
            favorites = library.favorites
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }

    func loadPlaylists(using client: DeezerClient) async {
        if let library = try? await client.library() {
            playlists = library.playlists
        }
    }

    func clear() {
        home = nil
        albums = []
        artists = []
        playlists = []
        favorites = []
        isLoading = false
        failure = nil
    }
}
