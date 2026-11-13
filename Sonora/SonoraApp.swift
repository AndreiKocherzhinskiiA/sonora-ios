import SwiftUI

@main
struct SonoraApp: App {
    @State private var library = LocalLibrary()
    @State private var playback: PlaybackController
    @State private var toasts = Toasts()
    @State private var youtube = YouTubeSession()
    @State private var feed = YouTubeFeed()
    @State private var subsonic = SubsonicSession()
    @State private var subsonicFeed = SubsonicFeed()
    @State private var deezer = DeezerSession()
    @State private var deezerFeed = DeezerFeed()
    @State private var lyrics = LyricsService()
    @State private var router = Router()
    @State private var history = PlayHistory()

    @State private var offline: OfflineMusic

    init() {
        let downloads = OfflineMusic()
        _offline = State(initialValue: downloads)
        _playback = State(initialValue: PlaybackController(offline: downloads))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(playback)
                .environment(toasts)
                .environment(youtube)
                .environment(feed)
                .environment(subsonic)
                .environment(subsonicFeed)
                .environment(deezer)
                .environment(deezerFeed)
                .environment(lyrics)
                .environment(router)
                .environment(history)
                .environment(offline)
                .task {
                    playback.setLibrary(library)
                    youtube.restore()
                    playback.setYouTube(youtube)
                    subsonic.restore()
                    playback.setSubsonic(subsonic)
                    offline.setSubsonic(subsonic.client)
                    deezer.restore()
                    playback.setDeezer(deezer)
                    offline.setDeezer(deezer.client)
                    history.restore()
                    offline.recover(history.tracks)
                    playback.setHistory(history)
                    await library.restore()
                }
        }
    }
}

