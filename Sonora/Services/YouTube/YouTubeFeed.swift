import Foundation
import Observation
import os

/// What the signed-in YouTube Music account shows in the app: the home page and the library's
/// playlists. Views read it, and `RootView` refreshes it when the account changes. It empties on
/// sign-out so a later account never sees the last one's music.
@Observable
final class YouTubeFeed {
    private(set) var home: YouTubeHome?
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [SavedArtist] = []
    private(set) var isLoading = false
    /// Why the last refresh failed, or nil.
    private(set) var failure: String?

    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "youtube")

    @ObservationIgnored private var generation = UUID()

    /// Loads the home page and the library playlists with `client`, or empties the feed for nil.
    func refresh(using client: YouTubeClient?) async {
        let request = UUID()
        generation = request
        guard let client else {
            isLoading = false
            home = nil
            playlists = []
            albums = []
            artists = []
            failure = nil
            return
        }
        isLoading = true
        failure = nil
        defer { if generation == request { isLoading = false } }

        async let homeResult = result {
            try await client.home { value in
                guard self.generation == request, !Task.isCancelled else { return }
                self.home = value
            }
        }
        async let playlistResult = result { try await client.libraryPlaylists() }
        async let albumResult = result { try await client.libraryAlbums() }
        async let artistResult = result { try await client.savedArtists() }
        let loadedHome = await homeResult
        guard generation == request, !Task.isCancelled else { return }
        switch loadedHome {
        case .success(let value): home = value
        case .failure(let error): report("home", error)
        }
        let loadedPlaylists = await playlistResult
        guard generation == request, !Task.isCancelled else { return }
        switch loadedPlaylists {
        case .success(let value): playlists = value
        case .failure(let error): report("library playlists", error)
        }
        let (loadedAlbums, loadedArtists) = await (albumResult, artistResult)
        guard generation == request, !Task.isCancelled else { return }
        if case .success(let value) = loadedAlbums { albums = value }
        if case .success(let value) = loadedArtists { artists = value }
    }

    /// Loads playlist choices on demand when the song actions open before the home refresh.
    func loadPlaylists(using client: YouTubeClient) async {
        let request = generation
        do {
            let loaded = try await client.libraryPlaylists()
            guard generation == request, !Task.isCancelled else { return }
            playlists = loaded
        } catch { report("library playlists", error) }
    }

    private func result<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private func report(_ what: String, _ error: Error) {
        logger.error("cannot load youtube \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        failure = error.localizedDescription
    }
}
