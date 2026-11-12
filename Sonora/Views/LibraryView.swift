import SwiftUI
import UniformTypeIdentifiers

/// The imported songs list with an import action, the phone form of the desktop Local Music page.
struct LibraryView: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(LocalLibrary.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(Toasts.self) private var toasts
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @State private var showsImporter = false

    private var showsYouTube: Bool { youtube.isSignedIn }

    var body: some View {
        Page("Your Library") {
            Button { showsImporter = true } label: {
                Icon("plus", size: 20).foregroundStyle(Theme.foreground)
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(library.isImporting)
            .accessibilityLabel("Import")
        } content: {
            if library.tracks.isEmpty && !showsYouTube && offline.tracks.isEmpty && offline.jobs.isEmpty {
                Vacancy(
                    icon: "file-music",
                    title: "No songs yet",
                    message: "Choose audio files stored on this iPhone or in iCloud Drive."
                ) {
                    Button("Import music") { showsImporter = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                List {
                    Section {
                        NavigationLink("Offline music") {
                            DownloadsView().navigationTitle("Offline music")
                        }
                        NavigationLink(value: YouTubeDestination.history) {
                            HStack(spacing: 12) {
                                Icon("music", size: 18).foregroundStyle(Theme.mutedForeground).frame(width: Theme.thumb)
                                Text("History").font(.bodyStrong).foregroundStyle(Theme.foreground)
                                Spacer(minLength: 0)
                            }
                            .frame(height: Theme.listRow)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: Theme.inset, bottom: 0, trailing: Theme.inset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden)
                    if showsYouTube {
                        if !feed.albums.isEmpty {
                            Section {
                                ForEach(feed.albums) { album in
                                    LibraryLink(artwork: album.artworkURL, title: album.title, subtitle: album.artists, destination: .album(album))
                                }
                            } header: {
                                Eyebrow("Saved albums").padding(.horizontal, Theme.inset).padding(.vertical, 8).textCase(nil)
                            }
                            .listSectionSeparator(.hidden)
                        }
                        if !feed.artists.isEmpty {
                            Section {
                                ForEach(feed.artists) { artist in
                                    LibraryLink(artwork: artist.artworkURL, title: artist.name, subtitle: "", destination: .artist(id: artist.id, name: artist.name), round: true)
                                }
                            } header: {
                                Eyebrow("Saved artists").padding(.horizontal, Theme.inset).padding(.vertical, 8).textCase(nil)
                            }
                            .listSectionSeparator(.hidden)
                        }
                        Section {
                            YouTubePlaylistLink(
                                playlist: Playlist(id: YouTubeClient.likedSongs, title: String(localized: "Liked music"), owner: "", artworkURL: nil, trackCount: 0)
                            )
                            ForEach(feed.playlists) { playlist in
                                YouTubePlaylistLink(playlist: playlist)
                            }
                        } header: {
                            Eyebrow("YouTube Music")
                                .padding(.horizontal, Theme.inset)
                                .padding(.vertical, 8)
                                .textCase(nil)
                        }
                        .listSectionSeparator(.hidden)
                    }
                    if !library.tracks.isEmpty {
                    Section {
                        ForEach(library.tracks) { track in
                            TrackRow(track: track) {
                                playback.play(track, from: library.tracks)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) { remove(track) }
                                    .tint(Theme.danger)
                            }
                        }
                    } header: {
                        LibraryHeader(count: library.tracks.count)
                    }
                    .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .overlay {
            if library.isImporting {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.foreground)
                    Text("Importing…").font(.bodyStrong).foregroundStyle(Theme.foreground)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.popover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                )
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await library.importFiles(urls) }
        }
        .onChange(of: library.errorMessage) {
            guard let message = library.errorMessage else { return }
            toasts.post(Toast(.failed, String(localized: "Library error")).detail(message))
            library.errorMessage = nil
        }
    }

    /// Removes a song and offers Undo. The file is deleted once the toast goes without it.
    private func remove(_ track: Track) {
        guard let index = library.remove(track) else { return }
        let message = String(localized: "Removed \(track.title) from your library")
        toasts.post(
            Toast(.done, message)
                .undo { library.restore(track, at: index) }
                .onExpire { library.purge(track) }
        )
    }
}

/// Song count and a Play button above the list, like the desktop hero strip.
private struct LibraryHeader: View {
    @Environment(LocalLibrary.self) private var library
    @Environment(PlaybackController.self) private var playback
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Music").font(.largeText).foregroundStyle(Theme.foreground)
                Text("\(count) songs").font(.small).foregroundStyle(Theme.mutedForeground)
            }
            Spacer()
            Button {
                if let first = library.tracks.first { playback.play(first, from: library.tracks) }
            } label: {
                HStack(spacing: 6) {
                    Icon("play-filled", size: 14)
                    Text("Play")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, 8)
        .textCase(nil)
        .background(Theme.background)
    }
}

/// A single song: cover thumb, title and artist, duration, and a menu of what can be done with it.
/// Flat, with a pressed highlight.
struct TrackRow: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(PlaybackController.self) private var playback
    let track: Track
    /// Set in the queue, where the menu can take the song out.
    var inQueue = false
    let action: () -> Void
    @State private var showsActions = false

    var body: some View {
        row
        .trackSheet(track, inQueue: inQueue, isPresented: $showsActions)
    }

    private var row: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, size: Theme.thumb)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.bodyStrong)
                            .foregroundStyle(isCurrent ? Theme.selection : Theme.foreground)
                            .lineLimit(1)
                        Text(track.subtitle)
                            .font(.small)
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let job = offline.job(for: track) {
                        ProgressView(value: job.fraction ?? 0).frame(width: 24)
                            .tint(Theme.foreground)
                            .accessibilityLabel("Download progress")
                    } else if offline.localURL(for: track) != nil {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.mutedForeground)
                            .accessibilityLabel("Downloaded")
                    }
                    if track.duration > 0 {
                        Text(track.duration.formattedDuration)
                            .font(.small.monospacedDigit())
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .padding(.leading, Theme.inset)
                .frame(height: Theme.listRow)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel("Play \(track.title)")

            Button { showsActions = true } label: {
                Icon("ellipsis", size: 18)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 44, height: Theme.listRow)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
            .padding(.trailing, 4)
        }
        .background(Theme.background)
    }

    private var isCurrent: Bool { playback.currentTrack?.id == track.id }
}

/// Row press feedback, the desktop `table_hover` fill.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.hover : .clear)
    }
}

/// Square cover with the placeholder music note the desktop `Artwork` shows when there is no image.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var radius: CGFloat = Theme.radius

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Theme.muted
                Icon("music", size: size * 0.4).foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.hairline)
        )
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A playlist of the YouTube Music library as a row that opens its songs.
private struct YouTubePlaylistLink: View {
    let playlist: Playlist

    var body: some View {
        NavigationLink(value: YouTubeDestination.playlist(playlist)) {
            HStack(spacing: 12) {
                ArtworkView(url: playlist.artworkURL, size: Theme.thumb)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.bodyStrong).foregroundStyle(Theme.foreground).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(.small).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(height: Theme.listRow)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.inset, bottom: 0, trailing: Theme.inset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var detail: String {
        [playlist.owner, playlist.trackCount > 0 ? String(localized: "\(playlist.trackCount) songs") : ""]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

/// A row of the library that opens a page.
private struct LibraryLink: View {
    let artwork: URL?
    let title: String
    let subtitle: String
    let destination: YouTubeDestination
    var round = false

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                ArtworkView(url: artwork, size: Theme.thumb, radius: round ? Theme.thumb / 2 : Theme.radius)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.bodyStrong).foregroundStyle(Theme.foreground).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.small).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(height: Theme.listRow)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.inset, bottom: 0, trailing: Theme.inset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
