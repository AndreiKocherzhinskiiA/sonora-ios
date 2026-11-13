import SwiftUI

/// A Subsonic / Navidrome artist page showing artwork and discography albums.
struct SubsonicArtistView: View {
    @Environment(SubsonicSession.self) private var subsonic
    @Environment(Toasts.self) private var toasts

    let id: String
    let name: String

    @State private var artist: SubsonicArtist?
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
                        if let count = artist?.albums.count, count > 0 {
                            Text("\(count) albums")
                                .font(.small)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.inset)
                .padding(.top, 12)

                if let artist, !artist.albums.isEmpty {
                    YouTubeShelfView(
                        title: String(localized: "Albums"),
                        items: artist.albums.map(YouTubeItem.subsonicAlbum)
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
            guard let client = subsonic.client else { return }
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
