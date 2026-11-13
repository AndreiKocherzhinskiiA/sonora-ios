import Foundation
import Observation

/// Holds the Subsonic / Navidrome home shelves and library collections across tabs.
@Observable
final class SubsonicFeed {
    private(set) var home: SubsonicHome?
    private(set) var albums: [Album] = []
    private(set) var artists: [SavedArtist] = []
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var failure: String?

    func refresh(using client: SubsonicClient?) async {
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
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }

    func clear() {
        home = nil
        albums = []
        artists = []
        playlists = []
        isLoading = false
        failure = nil
    }
}
