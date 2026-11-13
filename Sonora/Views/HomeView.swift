import SwiftUI

/// Home: quick picks as a two-column grid of compact cards, then recently added songs.
struct HomeView: View {
    @Environment(LocalLibrary.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @Environment(SubsonicSession.self) private var subsonic
    @Environment(SubsonicFeed.self) private var subsonicFeed
    @Environment(DeezerSession.self) private var deezer
    @Environment(DeezerFeed.self) private var deezerFeed

    @Environment(OfflineMusic.self) private var offline
    @Environment(PlayHistory.self) private var history

    private var recent: [YouTubeItem] {
        var seen = Set<Track.Source>()
        return history.tracks.filter { seen.insert($0.source).inserted }.prefix(20).map(YouTubeItem.track)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        Page("Home") {
            NavigationLink {
                DownloadsView().navigationTitle("Offline music")
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.foreground)
                    .frame(width: Theme.control, height: Theme.control)
            }
            .accessibilityLabel("Offline music")
        } content: {
            if library.tracks.isEmpty && !youtube.isSignedIn && !subsonic.isSignedIn && !deezer.isSignedIn && offline.tracks.isEmpty {
                Vacancy(
                    icon: "music",
                    title: "Your music, in one place",
                    message: "Import songs from Files, or sign in to a music provider in Settings."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if youtube.isSignedIn {
                            youtubeContent
                        }
                        if deezer.isSignedIn {
                            deezerContent
                        }
                        if subsonic.isSignedIn {
                            subsonicContent
                        }
                        if !library.tracks.isEmpty {
                            localContent
                        }
                    }
                    .padding(.bottom, 16)
                }
                .refreshable {
                    async let yt: Void = feed.refresh(using: youtube.client)
                    async let dz: Void = deezerFeed.refresh(using: deezer.client)
                    async let sub: Void = subsonicFeed.refresh(using: subsonic.client)
                    _ = await (yt, dz, sub)
                }
            }
        }
    }

    @ViewBuilder
    private var youtubeContent: some View {
        if !recent.isEmpty {
            YouTubeShelfView(title: String(localized: "Listen again"), items: recent)
        }
        if let home = feed.home {
            if recent.isEmpty, !home.listenAgain.isEmpty {
                YouTubeShelfView(title: String(localized: "Listen again"), items: home.listenAgain)
            }
            if !home.quickPicks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick picks")
                        .font(.largeText)
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, Theme.inset)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(home.quickPicks) { track in
                            QuickPick(track: track) {
                                playback.play(track, from: home.quickPicks)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.inset)
                }
            }
            ForEach(home.shelves) { shelf in
                YouTubeShelfView(title: shelf.title, items: shelf.items)
            }
        }
        if feed.isLoading {
            ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        if let failure = feed.failure {
            VStack(spacing: 12) {
                Text(failure).font(.small).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { Task { await feed.refresh(using: youtube.client) } }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, Theme.inset)
        }
    }

    @ViewBuilder
    private var subsonicContent: some View {
        if let home = subsonicFeed.home {
            if !home.quickPicks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(youtube.isSignedIn ? "Subsonic quick picks" : "Quick picks")
                        .font(.largeText)
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, Theme.inset)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(home.quickPicks.prefix(6)) { track in
                            QuickPick(track: track) {
                                playback.play(track, from: home.quickPicks)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.inset)
                }
            }
            ForEach(home.shelves) { shelf in
                YouTubeShelfView(title: shelf.title, items: shelf.items)
            }
        }
        if subsonicFeed.isLoading {
            ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        if let failure = subsonicFeed.failure {
            VStack(spacing: 12) {
                Text(failure).font(.small).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { Task { await subsonicFeed.refresh(using: subsonic.client) } }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, Theme.inset)
        }
    }

    @ViewBuilder
    private var deezerContent: some View {
        if !youtube.isSignedIn, !recent.isEmpty {
            YouTubeShelfView(title: String(localized: "Listen again"), items: recent)
        }
        if let home = deezerFeed.home {
            if !home.quickPicks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(youtube.isSignedIn ? "Deezer quick picks" : "Quick picks")
                        .font(.largeText)
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, Theme.inset)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(home.quickPicks.prefix(6)) { track in
                            QuickPick(track: track) {
                                playback.play(track, from: home.quickPicks)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.inset)
                }
            }
            ForEach(home.shelves) { shelf in
                YouTubeShelfView(title: shelf.title, items: shelf.items)
            }
        }
        if deezerFeed.isLoading {
            ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        if let failure = deezerFeed.failure {
            VStack(spacing: 12) {
                Text(failure).font(.small).foregroundStyle(Theme.mutedForeground)
                Button("Try again") { Task { await deezerFeed.refresh(using: deezer.client) } }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, Theme.inset)
        }
    }

    @ViewBuilder
    private var localContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Recently added")
                .padding(.horizontal, Theme.inset)
                .padding(.bottom, 8)
            ForEach(library.tracks.suffix(8).reversed()) { track in
                TrackRow(track: track) {
                    playback.play(track, from: library.tracks)
                }
            }
        }
    }
}

/// Compact card with a cover and a two-line title, the desktop `track_card`.
private struct QuickPick: View {
    let track: Track
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: track.artworkURL, size: 48, radius: Theme.radius)
            Text(track.title)
                .font(.label)
                .foregroundStyle(Theme.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
        .trackCard(track, play: action)
    }
}
