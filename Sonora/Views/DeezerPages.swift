import SwiftUI

/// A Deezer artist page showing top songs and discography albums.
struct DeezerArtistView: View {
    @Environment(DeezerSession.self) private var deezer
    @Environment(PlaybackController.self) private var playback
    @Environment(Toasts.self) private var toasts

    let id: String
    let name: String

    @State private var artist: YouTubeArtist?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    ArtworkView(url: artist?.artworkURL, size: 96, radius: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist?.name ?? name)
                            .font(.titleText)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                        if let fans = artist?.subscribers {
                            Text(fans)
                                .font(.small)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.inset)
                .padding(.top, 12)

                if let top = artist?.topTracks.first {
                    Button {
                        playback.play(top, from: artist?.topTracks)
                    } label: {
                        HStack(spacing: 6) {
                            Icon("play", size: 15)
                            Text("Play")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.inset)
                }

                if let artist, !artist.topTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Songs")
                            .font(.largeText)
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, Theme.inset)
                            .padding(.bottom, 8)
                        ForEach(artist.topTracks) { track in
                            TrackRow(track: track) {
                                playback.play(track, from: artist.topTracks)
                            }
                        }
                    }
                }

                if let artist, !artist.albums.isEmpty {
                    YouTubeShelfView(
                        title: String(localized: "Albums"),
                        items: artist.albums.map(YouTubeItem.deezerAlbum)
                    )
                } else if isLoading {
                    ProgressView()
                        .tint(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let client = deezer.client else { return }
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
}
