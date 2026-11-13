import SwiftUI

/// One titled row of cards that scrolls sideways, a YouTube Music home shelf.
struct YouTubeShelfView: View {
    @Environment(PlaybackController.self) private var playback
    let title: String
    let items: [YouTubeItem]

    private var tracks: [Track] {
        items.compactMap { if case .track(let track) = $0 { track } else { nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeText)
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, Theme.inset)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        card(for: item)
                    }
                }
                .padding(.horizontal, Theme.inset)
            }
        }
    }

    @ViewBuilder
    private func card(for item: YouTubeItem) -> some View {
        switch item {
        case .track(let track):
            ShelfCard(artwork: track.artworkURL, title: track.title, subtitle: track.subtitle)
                .trackCard(track) { playback.play(track, from: tracks) }
        case .playlist(let playlist):
            NavigationLink(value: YouTubeDestination.playlist(playlist)) {
                ShelfCard(artwork: playlist.artworkURL, title: playlist.title, subtitle: playlist.owner)
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink(value: YouTubeDestination.album(album)) {
                ShelfCard(artwork: album.artworkURL, title: album.title, subtitle: album.artists)
            }
            .buttonStyle(.plain)
        case .subsonicPlaylist(let playlist):
            NavigationLink(value: YouTubeDestination.subsonicPlaylist(playlist)) {
                ShelfCard(artwork: playlist.artworkURL, title: playlist.title, subtitle: playlist.owner)
            }
            .buttonStyle(.plain)
        case .subsonicAlbum(let album):
            NavigationLink(value: YouTubeDestination.subsonicAlbum(album)) {
                ShelfCard(artwork: album.artworkURL, title: album.title, subtitle: album.artists)
            }
            .buttonStyle(.plain)
        case .deezerPlaylist(let playlist):
            NavigationLink(value: YouTubeDestination.deezerPlaylist(playlist)) {
                ShelfCard(artwork: playlist.artworkURL, title: playlist.title, subtitle: playlist.owner)
            }
            .buttonStyle(.plain)
        case .deezerAlbum(let album):
            NavigationLink(value: YouTubeDestination.deezerAlbum(album)) {
                ShelfCard(artwork: album.artworkURL, title: album.title, subtitle: album.artists)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A square cover with a title and a muted line under it.
private struct ShelfCard: View {
    let artwork: URL?
    let title: String
    let subtitle: String

    private let side: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: artwork, size: side)
            Text(title)
                .font(.label)
                .foregroundStyle(Theme.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.small)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
    }
}

/// A playlist or album: its songs, loaded when the page opens, with a Play button.
struct YouTubeCollectionView: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(PlaybackController.self) private var playback
    @Environment(Toasts.self) private var toasts

    let title: String
    let subtitle: String
    let artwork: URL?
    let load: () async throws -> [Track]

    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Group {
                HStack(spacing: 14) {
                    ArtworkView(url: artwork, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.largeText).foregroundStyle(Theme.foreground).lineLimit(3)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.small).foregroundStyle(Theme.mutedForeground).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.inset)
                .padding(.vertical, 12)

                if let first = tracks.first {
                    Button {
                        playback.play(first, from: tracks)
                    } label: {
                        HStack(spacing: 6) {
                            Icon("play-filled", size: 14)
                            Text("Play")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.inset)
                    .padding(.bottom, 12)
                }

                if !tracks.isEmpty {
                    CollectionDownloadControl(tracks: tracks)
                        .padding(.bottom, 12)
                }
                if isLoading {
                    ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.top, 24)
                }
                ForEach(tracks) { track in
                    TrackRow(track: track) { playback.play(track, from: tracks) }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            do {
                tracks = try await load()
            } catch is CancellationError {
                return
            } catch {
                toasts.post(Toast(.failed, String(localized: "Could not load that")).detail(error.localizedDescription))
            }
        }
    }
}
