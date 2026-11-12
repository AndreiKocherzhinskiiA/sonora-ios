import SwiftUI

/// Lyrics of the playing track: synced lines that follow the music and jump to a tapped line, or a
/// plain sheet when the source has no timing.
struct LyricsView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(LyricsService.self) private var lyrics
    @Environment(YouTubeSession.self) private var youtube

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                ProgressView().tint(Theme.mutedForeground).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing:
                Vacancy(icon: "mic-vocal", title: "No lyrics for this song")
            case .failed(let message):
                Vacancy(icon: "mic-vocal", title: "Lyrics could not be loaded", message: LocalizedStringKey(message))
            case .found(.plain(let text), let source):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(text)
                            .font(.bodyText)
                            .foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Eyebrow(LocalizedStringKey("Lyrics from \(source)"))
                    }
                    .padding(Theme.inset)
                }
            case .found(.synced(let lines), let source):
                Synced(lines: lines, source: source)
            }
        }
        .task(id: playback.currentTrack?.id) {
            guard let track = playback.currentTrack else { return }
            await lyrics.load(for: track, length: playback.duration, youtube: youtube.client)
        }
    }
}

private struct Synced: View {
    @Environment(PlaybackController.self) private var playback
    let lines: [LyricLine]
    let source: String
    @State private var followsPlayback: Bool = {
        if #available(iOS 18.0, *) { return true }
        return false
    }()

    /// The last line whose time has come, a little early so the eye leads the voice.
    private var active: Int? {
        lines.lastIndex { $0.start <= playback.position + 0.25 }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(lines) { line in
                        Button { playback.seek(to: line.start) } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.largeText)
                                .foregroundStyle(Theme.foreground.opacity(line.id == active ? 1 : 0.4))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }
                    Eyebrow(LocalizedStringKey("Lyrics from \(source)"))
                        .padding(.top, 8)
                }
                .padding(Theme.inset)
                .animation(Appearance.shared.animation(0.25), value: active)
            }
            .modifier(LyricsScrollTracking(followsPlayback: $followsPlayback))
            .safeAreaInset(edge: .bottom) {
                Button {
                    followsPlayback.toggle()
                    if followsPlayback, let active {
                        withAnimation(Appearance.shared.animation(0.25)) { proxy.scrollTo(active, anchor: .center) }
                    }
                } label: {
                    Label(followsPlayback ? "Following lyrics" : "Follow lyrics", systemImage: followsPlayback ? "pause" : "arrow.down")
                        .font(.small).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.foreground)
                .background(Theme.background)
                .accessibilityHint("Turn lyric following on or off to read at your own pace.")
            }
            .onChange(of: active) {
                guard followsPlayback, let active else { return }
                withAnimation(Appearance.shared.animation(0.35)) { proxy.scrollTo(active, anchor: .center) }
            }
        }
    }
}

/// Observes the native scroll lifecycle without adding a competing drag recognizer.
private struct LyricsScrollTracking: ViewModifier {
    @Binding var followsPlayback: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { followsPlayback = false }
            }
        } else {
            // iOS 17 starts with manual scrolling; the visible Follow control remains available.
            content
        }
    }
}
