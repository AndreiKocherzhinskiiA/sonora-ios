import SwiftUI

/// Song actions shown by a row menu button or by holding a Home card.
struct TrackSheet: View {
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @Environment(Toasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    let track: Track
    var inQueue = false
    @State private var choosingPlaylist = false

    private var videoID: String? {
        if case .youtube(let id) = track.source { id } else { nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(url: track.artworkURL, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.bodyStrong).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text(track.subtitle).font(.small).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 24)
            .padding(.bottom, 12)
            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    switch choosingPlaylist {
                    case true: playlists
                    case false:
                        TrackActions(track: track, inQueue: inQueue, done: { dismiss() }) {
                            choosingPlaylist = true
                        }
                    }
                }
                .buttonStyle(SheetRowStyle())
                .labelStyle(SheetRowLabelStyle())
            }
        }
        .background(Theme.background)
        .task {
            if feed.playlists.isEmpty, let client = youtube.client {
                await feed.loadPlaylists(using: client)
            }
        }
    }

    @ViewBuilder
    private var playlists: some View {
        Button { choosingPlaylist = false } label: { Label("Back", systemImage: "chevron.backward") }
        if let videoID, let client = youtube.client {
            ForEach(feed.playlists) { playlist in
                Button {
                    dismiss()
                    let toasts = toasts
                    Task { @MainActor in
                        do {
                            try await client.add(videoID, toPlaylist: playlist.id)
                            toasts.post(Toast(.done, String(localized: "Added to \(playlist.title)")))
                        } catch {
                            toasts.post(
                                Toast(.failed, String(localized: "Could not add that to \(playlist.title)"))
                                    .detail(error.localizedDescription)
                            )
                        }
                    }
                } label: {
                    Label(playlist.title, systemImage: "music.note.list")
                }
            }
        }
    }
}

/// The actions themselves, as plain buttons, so the same list fills both the sheet (styled as rows)
/// and a `.contextMenu` (drawn by the system, which leaves scrolling alone).
struct TrackActions: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @Environment(Toasts.self) private var toasts
    @Environment(Router.self) private var router

    let track: Track
    var inQueue = false
    /// Closes whatever shows the actions. A context menu closes itself, so it passes nothing.
    var done: () -> Void = {}
    /// Opens the sheet's playlist picker. Without it, the playlists are a submenu.
    var choosePlaylist: (() -> Void)?

    private var videoID: String? {
        if case .youtube(let id) = track.source { id } else { nil }
    }

    var body: some View {
        Button {
            playback.playNext(track)
            toasts.post(Toast(.done, String(localized: "\(track.title) plays next")))
            done()
        } label: {
            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            playback.playLast(track)
            toasts.post(Toast(.done, String(localized: "\(track.title) plays last")))
            done()
        } label: {
            Label("Play last", systemImage: "text.line.last.and.arrowtriangle.forward")
        }

        if offline.localURL(for: track) != nil {
            Button(role: .destructive) { offline.remove(track); done() } label: {
                Label("Remove download", systemImage: "trash")
            }
        }
        if videoID != nil, let client = youtube.client {
            Button {
                done()
                Task { await offline.download([track], using: client) }
            } label: {
                Label(offline.localURL(for: track) != nil ? "Downloaded" : offline.job(for: track) != nil ? "Queued for download" : "Download", systemImage: "arrow.down.circle")
            }
            .disabled(offline.localURL(for: track) != nil || offline.job(for: track) != nil)
            Button {
                done()
                let toasts = toasts
                Task { @MainActor in
                    do { try await playback.startRadio(for: track, using: client) }
                    catch { toasts.post(Toast(.failed, String(localized: "Could not start radio")).detail(error.localizedDescription)) }
                }
            } label: {
                Label("Start radio", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        if let artist = track.artistReferences.first(where: { $0.id != nil }), let artistID = artist.id {
            Button { open(.artist(id: artistID, name: artist.name)) } label: {
                Label("Go to artist", systemImage: "person.crop.circle")
            }
        }
        if let albumID = track.albumID {
            Button {
                open(.album(Album(id: albumID, title: track.album, artists: track.artists, artworkURL: track.artworkURL, year: 0, trackCount: 0)))
            } label: {
                Label("Go to album", systemImage: "square.stack")
            }
        }

        if let videoID, let client = youtube.client {
            Button {
                change(String(localized: "Added to Liked music"), String(localized: "Could not add that to Liked music")) {
                    try await client.rate(videoID, liked: true)
                }
            } label: {
                Label("Add to Liked music", systemImage: "heart")
            }
            Button {
                change(String(localized: "Removed from Liked music"), String(localized: "Could not remove that from Liked music")) {
                    try await client.rate(videoID, liked: false)
                }
            } label: {
                Label("Remove from Liked music", systemImage: "heart.slash")
            }
            if choosePlaylist != nil || !feed.playlists.isEmpty {
                if let choosePlaylist {
                    Button(action: choosePlaylist) { Label("Add to playlist", systemImage: "text.badge.plus") }
                } else {
                    Menu {
                        ForEach(feed.playlists) { playlist in
                            Button(playlist.title) {
                                change(String(localized: "Added to \(playlist.title)"), String(localized: "Could not add that to \(playlist.title)")) {
                                    try await client.add(videoID, toPlaylist: playlist.id)
                                }
                            }
                        }
                    } label: {
                        Label("Add to playlist", systemImage: "text.badge.plus")
                    }
                }
            }
        }

        if track.sourceURL.scheme?.hasPrefix("http") == true {
            Button {
                UIPasteboard.general.string = track.sourceURL.absoluteString
                toasts.post(Toast(.done, String(localized: "Link copied")))
                done()
            } label: {
                Label("Copy link", systemImage: "link")
            }
            ShareLink(item: track.sourceURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        if inQueue, track.id != playback.currentTrack?.id {
            Button(role: .destructive) {
                playback.removeFromQueue(track)
                done()
            } label: {
                Label("Remove from queue", systemImage: "trash")
            }
        }
    }

    /// Closes the actions and, if the player is open, the player, then opens `destination`.
    private func open(_ destination: YouTubeDestination) {
        done()
        router.open(destination, fromPlayer: true)
    }

    /// Runs a change to the account, says how it went in a toast, and closes the actions.
    private func change(_ success: String, _ failure: String, _ work: @escaping () async throws -> Void) {
        done()
        let toasts = toasts
        Task { @MainActor in
            do {
                try await work()
                toasts.post(Toast(.done, success))
            } catch {
                toasts.post(Toast(.failed, failure).detail(error.localizedDescription))
            }
        }
    }
}

extension View {
    /// Presents the song sheet for `track` while `isPresented` is set.
    func trackSheet(_ track: Track, inQueue: Bool = false, isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            TrackSheet(track: track, inQueue: inQueue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .presentationContentInteraction(.scrolls)
        }
    }

    /// Makes a song card play on a tap and open the song sheet on a long press, the same sheet a
    /// row's ... button opens, for cards with no room for that button.
    func trackCard(_ track: Track, play: @escaping () -> Void) -> some View {
        modifier(TrackCard(track: track, play: play))
    }
}

/// Gestures rather than a Button, because a Button also fires its action when a long press lets go.
/// Both fail once the finger moves, so the scroll view keeps its drag.
private struct TrackCard: ViewModifier {
    let track: Track
    let play: () -> Void
    @State private var showsActions = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 10) { showsActions = true }
            .sensoryFeedback(.impact, trigger: showsActions) { _, shown in shown }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Play \(track.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, play)
            .accessibilityAction(named: "More") { showsActions = true }
            .trackSheet(track, isPresented: $showsActions)
    }
}

/// A full-width sheet row: icon, title, and the danger color for destructive actions.
private struct SheetRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Theme.danger : Theme.foreground)
            .background(configuration.isPressed ? Theme.hover : .clear)
    }
}

private struct SheetRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.icon.frame(width: 24)
            configuration.title.font(.bodyText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.inset)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}
