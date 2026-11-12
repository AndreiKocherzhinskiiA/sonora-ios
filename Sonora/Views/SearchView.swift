import SwiftUI

/// Search over the local library and, when signed in, YouTube Music, with the desktop's flat input
/// field and a filter for songs, albums, artists or playlists.
struct SearchView: View {
    enum Scope: CaseIterable, Identifiable {
        case songs, albums, artists, playlists

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .artists: "Artists"
            case .playlists: "Playlists"
            }
        }
    }

    @Environment(LocalLibrary.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSession.self) private var youtube
    @Environment(Toasts.self) private var toasts
    @State private var songs: [Track] = []
    @State private var albums: [Album] = []
    @State private var artists: [SavedArtist] = []
    @State private var playlists: [Playlist] = []
    @State private var isSearchingRemote = false
    @State private var scope: Scope = .songs
    @State private var query = ""
    @FocusState private var focused: Bool

    private var local: [Track] {
        guard !query.isEmpty else { return library.tracks }
        return library.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artists.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    private var hasRemote: Bool { youtube.isSignedIn && !query.isEmpty }

    private var isEmpty: Bool {
        guard !query.isEmpty, !isSearchingRemote else { return false }
        switch (hasRemote, scope) {
        case (false, _): return local.isEmpty
        case (true, .songs): return local.isEmpty && songs.isEmpty
        case (true, .albums): return albums.isEmpty
        case (true, .artists): return artists.isEmpty
        case (true, .playlists): return playlists.isEmpty
        }
    }

    var body: some View {
        Page("Search") {
            field
                .padding(.horizontal, Theme.inset)
                .padding(.bottom, 8)
            if hasRemote { scopes }

            if isEmpty {
                Vacancy(icon: "search", title: "No matches")
            } else {
                List {
                    results
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .task(id: query) { await searchRemote() }
        .task(id: scope) { await searchRemote() }
    }

    @ViewBuilder
    private var results: some View {
        let showsSongs = !hasRemote || scope == .songs
        if showsSongs {
            Eyebrow(query.isEmpty ? "Songs" : "Results")
                .padding(.horizontal, Theme.inset)
                .padding(.bottom, 8)
            ForEach(local) { track in
                TrackRow(track: track) { playback.play(track, from: local) }
            }
        }
        if hasRemote {
            if isSearchingRemote {
                ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            switch scope {
            case .songs:
                if !songs.isEmpty {
                    Eyebrow("YouTube Music")
                        .padding(.horizontal, Theme.inset)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }
                ForEach(songs) { track in
                    TrackRow(track: track) { playback.play(track, from: songs) }
                }
            case .albums:
                ForEach(albums) { album in
                    ResultRow(
                        artwork: album.artworkURL, title: album.title,
                        subtitle: [album.artists, album.year > 0 ? String(album.year) : ""]
                            .filter { !$0.isEmpty }.joined(separator: " • "),
                        destination: .album(album)
                    )
                }
            case .artists:
                ForEach(artists) { artist in
                    ResultRow(
                        artwork: artist.artworkURL, title: artist.name, subtitle: "",
                        destination: .artist(id: artist.id, name: artist.name), round: true
                    )
                }
            case .playlists:
                ForEach(playlists) { playlist in
                    ResultRow(
                        artwork: playlist.artworkURL, title: playlist.title, subtitle: playlist.owner,
                        destination: .playlist(playlist)
                    )
                }
            }
        }
    }

    private var scopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { entry in
                    Button { scope = entry } label: {
                        Text(entry.title)
                            .font(.label)
                            .foregroundStyle(scope == entry ? Theme.primaryForeground : Theme.foreground)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(scope == entry ? Theme.primary : Theme.secondary)
                            )
                            .overlay(Capsule().stroke(Theme.border, lineWidth: Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.inset)
        }
        .padding(.bottom, 12)
    }

    /// Searches YouTube Music once typing pauses, for the chosen kind of result. A failed search
    /// shows a toast and keeps the local results.
    private func searchRemote() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard youtube.isSignedIn, let client = youtube.client, !text.isEmpty else {
            songs = []; albums = []; artists = []; playlists = []
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        isSearchingRemote = true
        defer { isSearchingRemote = false }
        do {
            switch scope {
            case .songs: songs = try await client.searchSongs(text)
            case .albums: albums = try await client.searchAlbums(text)
            case .artists: artists = try await client.searchArtists(text)
            case .playlists: playlists = try await client.searchPlaylists(text)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            toasts.post(Toast(.failed, String(localized: "YouTube Music search failed")).detail(error.localizedDescription))
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Icon("search", size: 16).foregroundStyle(Theme.mutedForeground)
            TextField("", text: $query, prompt: Text("Songs, artists, and albums").foregroundColor(Theme.mutedForeground))
                .font(.bodyText)
                .foregroundStyle(Theme.foreground)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Icon("x", size: 14).foregroundStyle(Theme.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(focused ? Theme.foreground.opacity(0.5) : Theme.border, lineWidth: Theme.hairline)
        )
    }
}

/// A search result that opens a page: cover, title and a muted line.
struct ResultRow: View {
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
            .padding(.horizontal, Theme.inset)
            .frame(height: Theme.listRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
