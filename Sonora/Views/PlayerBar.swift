import SwiftUI

/// Compact player: cover, title and artist, previous/play/next, and a thin progress line on top.
/// Tapping it opens the full-screen player.
struct PlayerBar: View {
    @Environment(PlaybackController.self) private var playback
    @Binding var showsNowPlaying: Bool
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let track = playback.currentTrack {
            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 12) {
                    ArtworkView(url: track.artworkURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.bodyStrong)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Text(track.subtitle)
                            .font(.small)
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { playback.togglePlayback() } label: {
                        Icon(playback.state == .playing ? "pause-filled" : "play-filled", size: 20)
                            .foregroundStyle(Theme.foreground)
                    }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel(playback.state == .playing ? "Pause" : "Play")
                    Button { playback.next() } label: {
                        Icon("skip-forward", size: 20).foregroundStyle(Theme.foreground)
                    }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel("Next song")
                }
                .offset(x: dragOffset)
                .clipped()
                .padding(.horizontal, 12)
                .frame(height: Theme.playerBar)
                .background {
                    if Appearance.shared.blur {
                        Rectangle().fill(.ultraThinMaterial)
                    } else {
                        Theme.secondary
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { showsNowPlaying = true }
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .onChanged { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        dragOffset = min(max(drag.translation.width * 0.25, -36), 36)
                    }
                    .onEnded { drag in
                        if abs(drag.translation.width) > abs(drag.translation.height) {
                            if drag.translation.width < -50 { playback.next() }
                            else if drag.translation.width > 50 { playback.previous(restarting: false) }
                        }
                        withAnimation(Appearance.shared.animation(0.2)) { dragOffset = 0 }
                    })
                .sensoryFeedback(.selection, trigger: track.id)
                .overlay(alignment: .top) { Progress(track: track) }
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: "Open Now Playing") { showsNowPlaying = true }
            }
        }
    }
}

/// Two-point playback progress line along the top edge of the player bar.
private struct Progress: View {
    @Environment(PlaybackController.self) private var playback
    let track: Track

    var body: some View {
        GeometryReader { proxy in
            let fraction = playback.duration > 0 ? min(max(playback.position / playback.duration, 0), 1) : 0
            Rectangle()
                .fill(Theme.foreground)
                .frame(width: proxy.size.width * fraction, height: 2)
        }
        .frame(height: 2)
    }
}
