import SwiftUI

/// App shell: the active screen, the compact player bar and a flat tab bar, stacked like the
/// desktop sidebar, content and player bar.
struct RootView: View {
    enum Tab: Hashable, CaseIterable {
        case home
        case search
        case library
        case settings

        var icon: String {
            switch self {
            case .home: "house"
            case .search: "search"
            case .library: "library-big"
            case .settings: "settings"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .home: "Home"
            case .search: "Search"
            case .library: "Your Library"
            case .settings: "Settings"
            }
        }
    }

    @Environment(OfflineMusic.self) private var offline
    @Environment(PlayHistory.self) private var history
    @Environment(PlaybackController.self) private var playback
    @Environment(Toasts.self) private var toasts
    @Environment(YouTubeSession.self) private var youtube
    @Environment(YouTubeFeed.self) private var feed
    @Environment(SubsonicSession.self) private var subsonic
    @Environment(SubsonicFeed.self) private var subsonicFeed
    @Environment(DeezerSession.self) private var deezer
    @Environment(DeezerFeed.self) private var deezerFeed
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Tab = .home
    @State private var showsNowPlaying = false
    @State private var navigationReset = UUID()
    private var look: Appearance { .shared }

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
                Group {
                    switch selection {
                    case .home: HomeView()
                    case .search: SearchView()
                    case .library: LibraryView()
                    case .settings: SettingsView()
                    }
                }
                .navigationDestination(for: YouTubeDestination.self) { YouTubeDestinationView(destination: $0) }
            }
            .id(selection)
            .id(navigationReset)
            .onChange(of: selection) { router.path = [] }

            if playback.currentTrack != nil {
                PlayerBar(showsNowPlaying: $showsNowPlaying)
            }
            TabBar(selection: $selection) {
                router.path = []
                // Direct destination links also hold internal stack state. Recreate the stack on reselect.
                navigationReset = UUID()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            ToastStack()
                .padding(.bottom, Theme.tabBar + (playback.currentTrack != nil ? Theme.playerBar : 0) + 12)
        }
        .preferredColorScheme(look.colorScheme)
        .onAppear { look.systemIsDark = colorScheme == .dark }
        .onChange(of: colorScheme) { look.systemIsDark = colorScheme == .dark }
        .onChange(of: look.snapshot) { look.persist() }
        .onChange(of: router.closesPlayer) {
            if router.closesPlayer {
                showsNowPlaying = false
                router.closesPlayer = false
            }
        }
        .task(id: "\(youtube.isSignedIn)-\(offline.isConnected)") {
            guard offline.isConnected || !youtube.isSignedIn else { return }
            await feed.refresh(using: youtube.client)
            if let failure = feed.failure {
                toasts.post(Toast(.failed, String(localized: "Could not load YouTube Music")).detail(failure))
            }
        }
        .task(id: "\(subsonic.isSignedIn)-\(offline.isConnected)") {
            offline.setSubsonic(subsonic.client)
            guard offline.isConnected || !subsonic.isSignedIn else { return }
            await subsonicFeed.refresh(using: subsonic.client)
            if let failure = subsonicFeed.failure {
                toasts.post(Toast(.failed, String(localized: "Could not load Subsonic")).detail(failure))
            }
        }
        .task(id: "\(deezer.isSignedIn)-\(offline.isConnected)") {
            offline.setDeezer(deezer.client)
            guard offline.isConnected || !deezer.isSignedIn else { return }
            await deezerFeed.refresh(using: deezer.client)
            if let failure = deezerFeed.failure {
                toasts.post(Toast(.failed, String(localized: "Could not load Deezer")).detail(failure))
            }
        }
        .task(id: "\(offline.smartDownloads)-\(offline.smartDownloadsRunning)-\(offline.appliedSmartDownloadLimit)-\(youtube.isSignedIn)-\(subsonic.isSignedIn)-\(deezer.isSignedIn)-\(history.tracks.first?.id.uuidString ?? "")") {
            guard offline.smartDownloads, offline.smartDownloadsRunning,
                  youtube.client != nil || subsonic.client != nil || deezer.client != nil else { return }
            guard !Task.isCancelled else { return }
            await offline.download(
                offline.smartTracks(from: history.tracks, limit: offline.appliedSmartDownloadLimit),
                using: youtube.client,
                subsonic: subsonic.client,
                deezer: deezer.client
            )
        }
        .onChange(of: offline.failure) {
            if let failure = offline.failure {
                toasts.post(Toast(.failed, String(localized: "Download failed")).detail(failure))
            }
        }
        .task(id: playback.currentTrack?.id) {
            look.tint = await ArtworkTint.dominantColor(of: playback.currentTrack?.artworkURL)
        }
        .sheet(isPresented: $showsNowPlaying) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .onChange(of: playback.state) {
            guard case .failed(let message) = playback.state else { return }
            toasts.post(Toast(.failed, String(localized: "Playback error")).detail(message))
            playback.dismissError()
        }
    }
}

/// Bottom navigation: one icon and label per top-level destination, with a hairline above.
private struct TabBar: View {
    @Binding var selection: RootView.Tab
    let reselect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(RootView.Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(Appearance.shared.animation(0.15)) {
                            if selection == tab { reselect() }
                            else { selection = tab }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Icon(tab.icon, size: 20)
                            Text(tab.title).font(.tiny).lineLimit(1)
                        }
                        .foregroundStyle(selection == tab ? Theme.foreground : Theme.mutedForeground)
                        .frame(maxWidth: .infinity, minHeight: Theme.tabBar)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
        }
        .background {
            if Appearance.shared.blur {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .bottom)
            } else {
                Theme.background.ignoresSafeArea(edges: .bottom)
            }
        }
    }
}
