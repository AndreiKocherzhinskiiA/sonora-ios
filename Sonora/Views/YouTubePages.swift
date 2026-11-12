import SwiftUI

/// The page a `YouTubeDestination` opens.
struct YouTubeDestinationView: View {
    let destination: YouTubeDestination

    var body: some View {
        switch destination {
        case .artist(let id, let name):
            YouTubeArtistView(id: id, name: name)
        case .playlist(let playlist):
            YouTubeCollectionView(
                title: playlist.title,
                subtitle: playlist.owner,
                artwork: playlist.artworkURL,
                load: { client in try await client.playlistTracks(playlist.id) }
            )
        case .album(let album):
            YouTubeCollectionView(
                title: album.title,
                subtitle: album.artists,
                artwork: album.artworkURL,
                load: { client in try await client.albumTracks(album.id) }
            )
        case .history:
            HistoryView()
        }
    }
}

/// An artist page: top songs and releases, with a Play button and a way to save the artist.
struct YouTubeArtistView: View {
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @Environment(PlaybackController.self) private var playback
    @Environment(Toasts.self) private var toasts

    let id: String
    let name: String

    @State private var artist: YouTubeArtist?
    @State private var isLoading = true
    @State private var expanded = false

    private var isSaved: Bool { feed.artists.contains { $0.id == id } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if let artist {
                    if let text = artist.description {
                        Text(text)
                            .font(.small)
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(expanded ? nil : 4)
                            .padding(.horizontal, Theme.inset)
                            .onTapGesture { expanded.toggle() }
                    }
                    if !artist.topTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Songs")
                                .font(.largeText)
                                .foregroundStyle(Theme.foreground)
                                .padding(.horizontal, Theme.inset)
                                .padding(.bottom, 8)
                            ForEach(artist.topTracks) { track in
                                TrackRow(track: track) { playback.play(track, from: artist.topTracks) }
                            }
                        }
                    }
                    if !artist.albums.isEmpty {
                        YouTubeShelfView(title: String(localized: "Albums"), items: artist.albums.map(YouTubeItem.album))
                    }
                    if !artist.singles.isEmpty {
                        YouTubeShelfView(title: String(localized: "Singles & EPs"), items: artist.singles.map(YouTubeItem.album))
                    }
                } else if isLoading {
                    ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let client = youtube.client else { return }
            defer { isLoading = false }
            do {
                artist = try await client.artist(id)
            } catch is CancellationError {
                return
            } catch {
                toasts.post(Toast(.failed, String(localized: "Could not load that")).detail(error.localizedDescription))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkView(url: artist?.artworkURL, size: 96, radius: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(artist?.name ?? name).font(.titleText).foregroundStyle(Theme.foreground).lineLimit(2)
                if let subscribers = artist?.subscribers {
                    Text(subscribers).font(.small).foregroundStyle(Theme.mutedForeground)
                }
                HStack(spacing: 8) {
                    if let tracks = artist?.topTracks, let first = tracks.first {
                        Button { playback.play(first, from: tracks) } label: {
                            HStack(spacing: 6) { Icon("play-filled", size: 14); Text("Play") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    Button(isSaved ? "Saved" : "Save") { toggleSaved() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, 12)
    }

    private func toggleSaved() {
        guard let client = youtube.client else { return }
        let target = !isSaved
        Task { @MainActor in
            do {
                try await client.setSaved(artist: id, saved: target)
                await feed.refresh(using: client)
                toasts.post(Toast(.done, target
                    ? String(localized: "Saved \(name) to your library")
                    : String(localized: "Removed \(name) from your library")))
            } catch {
                toasts.post(Toast(.failed, String(localized: "Could not change your library")).detail(error.localizedDescription))
            }
        }
    }
}

/// Everything that has played on this iPhone, newest first.
struct HistoryView: View {
    @Environment(PlayHistory.self) private var history
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        Group {
            if history.tracks.isEmpty {
                Vacancy(icon: "music", title: "Nothing played yet", message: "Songs you listen to show up here.")
            } else {
                List {
                    ForEach(history.tracks) { track in
                        TrackRow(track: track) { playback.play(track, from: history.tracks) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.tracks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", role: .destructive) { history.clear() }
                }
            }
        }
    }
}
