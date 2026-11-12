import SwiftUI

/// Full-screen player: cover, title, scrubber and transport, with the desktop's flat
/// monochrome controls and a solid primary play button.
struct NowPlayingView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @State private var panel: NowPlayingPanel.Tab?
    /// How far the cover and title follow a sideways swipe, before it lets go.
    @State private var swipe: CGFloat = 0
    @State private var skipFeedback: Int?

    /// How far a swipe has to go to change the song.
    private let swipeThreshold: CGFloat = 80

    /// How many seconds a double tap on the cover jumps ahead.
    private let skipInterval: TimeInterval = 10

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon("chevron-down", size: 22).foregroundStyle(Theme.foreground)
                }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("Close")
                Spacer()
                Eyebrow("Now Playing")
                Spacer()
                if let track = playback.currentTrack {
                    Menu { TrackActions(track: track) } label: {
                        Icon("ellipsis", size: 22).foregroundStyle(Theme.foreground)
                    }
                    .buttonStyle(GhostButtonStyle())
                    .accessibilityLabel("Song actions")
                }

            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 16)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ArtworkView(url: playback.currentTrack?.artworkURL, size: side, radius: Theme.radius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        HStack(spacing: 0) {
                            seekZone(direction: -1)
                            seekZone(direction: 1)
                        }
                    }
            }
            .padding(.horizontal, Theme.inset)
            .frame(maxHeight: 360)
            .offset(x: swipe)
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(playback.currentTrack?.title ?? String(localized: "Nothing playing"))
                    .font(.titleText)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Text(playback.currentTrack?.subtitle ?? "")
                    .font(.bodyText)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.inset)
            .offset(x: swipe)
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)

            VStack(spacing: 8) {
                Scrubber(
                    value: Binding(
                        get: { playback.position },
                        set: { playback.seek(to: $0) }
                    ),
                    range: 0...max(playback.duration, 1)
                )
                HStack {
                    Text(playback.position.formattedDuration)
                    Spacer()
                    Text(playback.duration.formattedDuration)
                }
                .font(.small.monospacedDigit())
                .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 20)

            HStack(spacing: 0) {
                Button { playback.toggleShuffle() } label: {
                    Icon("shuffle", size: 20)
                        .foregroundStyle(playback.isShuffled ? Theme.foreground : Theme.mutedForeground)
                }
                .buttonStyle(GhostButtonStyle(size: 48))
                .accessibilityLabel("Shuffle")
                Spacer()
                Button { playback.previous() } label: {
                    Icon("skip-back", size: 26).foregroundStyle(Theme.foreground)
                }
                .buttonStyle(GhostButtonStyle(size: 48))
                .accessibilityLabel("Previous song")
                Spacer()
                Button { playback.togglePlayback() } label: {
                    Icon(playback.state == .playing ? "pause-filled" : "play-filled", size: 26)
                        .foregroundStyle(Theme.primaryForeground)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Theme.primary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.state == .playing ? "Pause" : "Play")
                Spacer()
                Button { playback.next() } label: {
                    Icon("skip-forward", size: 26).foregroundStyle(Theme.foreground)
                }
                .buttonStyle(GhostButtonStyle(size: 48))
                .accessibilityLabel("Next song")
                Spacer()
                Button { playback.advanceRepeatMode() } label: {
                    Icon(playback.repeatMode == .one ? "repeat-one" : "repeat", size: 20)
                        .foregroundStyle(playback.repeatMode == .off ? Theme.mutedForeground : Theme.foreground)
                }
                .buttonStyle(GhostButtonStyle(size: 48))
                .accessibilityLabel("Repeat")
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 20)

            Spacer(minLength: 16)

            PanelHandle {
                panel = .queue
            } minimize: {
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Ambient() }
        .task(id: skipFeedback) {
            guard skipFeedback != nil else { return }
            do { try await Task.sleep(for: .milliseconds(750)) }
            catch { return }
            withAnimation(Appearance.shared.animation(0.15)) { skipFeedback = nil }
        }
        .onChange(of: playback.currentTrack?.id) { skipFeedback = nil }
        .sensoryFeedback(.selection, trigger: skipFeedback) { _, value in value != nil }
        .sheet(item: $panel) { tab in
            NowPlayingPanel(tab: tab)
                .presentationDetents([.fraction(0.62), .large])
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    /// Cover/title swipes change songs horizontally and explicitly minimize on a downward drag.
    /// No page-wide drag recognizer competes with the sheet's native dismissal gesture.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                swipe = drag.translation.width
            }
            .onEnded { drag in
                let sideways = abs(drag.translation.width) > abs(drag.translation.height)
                if !sideways, panel == nil,
                   drag.translation.height > 60 || drag.translation.height > 12 && drag.predictedEndTranslation.height > 140 {
                    dismiss()
                } else if sideways, drag.translation.width <= -swipeThreshold {
                    playback.next()
                } else if sideways, drag.translation.width >= swipeThreshold {
                    playback.previous(restarting: false)
                }
                withAnimation(Appearance.shared.animation(0.2)) { swipe = 0 }
            }
    }

    /// Shows feedback on the tapped half, including cumulative seconds for repeated double taps.
    private func seekZone(direction: Int) -> some View {
        ZStack {
            Color.clear
            if let seconds = skipFeedback, (seconds < 0 ? -1 : 1) == direction {
                VStack(spacing: 8) {
                    Image(systemName: direction < 0 ? "gobackward.10" : "goforward.10")
                        .font(.title2)
                    Text("\(seconds > 0 ? "+" : "-")\(abs(seconds)) s")
                        .font(.bodyStrong.monospacedDigit())
                }
                .foregroundStyle(Theme.foreground)
                .padding(16)
                .background(Theme.popover.opacity(0.94), in: RoundedRectangle(cornerRadius: Theme.radius))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { skip(direction: direction) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction < 0 ? "Rewind 10 seconds" : "Forward 10 seconds")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { skip(direction: direction) }
    }

    private func skip(direction: Int) {
        guard playback.currentTrack != nil, playback.state == .playing || playback.state == .paused else { return }
        playback.skip(by: Double(direction) * skipInterval)
        let previous = skipFeedback ?? 0
        let sameDirection = previous != 0 && (previous < 0 ? -1 : 1) == direction
        withAnimation(Appearance.shared.animation(0.15)) {
            skipFeedback = sameDirection ? previous + direction * Int(skipInterval) : direction * Int(skipInterval)
        }
    }

}

/// Full-screen backdrop: the page background, plus soft blobs of the cover's color that drift
/// slowly when ambient motion is on. Shown only when the ambient setting is enabled.
private struct Ambient: View {
    @State private var drift = false

    var body: some View {
        let look = Appearance.shared
        ZStack {
            Theme.background
            if look.ambient, let tint = look.tint {
                let color = Color(tint)
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 420, height: 420)
                    .blur(radius: 90)
                    .offset(x: drift ? 80 : -80, y: drift ? -220 : -120)
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 360, height: 360)
                    .blur(radius: 90)
                    .offset(x: drift ? -90 : 90, y: drift ? 260 : 180)
            }
        }
        .ignoresSafeArea()
        .onAppear { updateDrift() }
        .onChange(of: look.ambientMotion) { updateDrift() }
        .onChange(of: look.reduceMotion) { updateDrift() }
    }

    private func updateDrift() {
        let look = Appearance.shared
        guard look.ambientMotion, !look.reduceMotion else {
            withAnimation(nil) { drift = false }
            return
        }
        withAnimation(.easeInOut(duration: 9 * look.pace.scale).repeatForever(autoreverses: true)) {
            drift = true
        }
    }
}

/// Thin seek bar with a draggable fill, the desktop `Scrubber`.
private struct Scrubber: View {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>

    private let height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(range.upperBound - range.lowerBound, 0.001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule().fill(Theme.foreground).frame(width: width * fraction)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let ratio = min(max(drag.location.x / max(width, 1), 0), 1)
                    value = range.lowerBound + span * ratio
                }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(value.formattedDuration)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 10, range.upperBound)
            case .decrement: value = max(value - 10, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// A single pull handle opens the drawer. Its tab choices live inside, with Up next first.
private struct PanelHandle: View {
    let open: () -> Void
    let minimize: () -> Void
    @State private var lift: CGFloat = 0

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                Capsule().fill(Theme.mutedForeground).frame(width: 44, height: 5)
                HStack(spacing: 6) {
                    Text("Queue & lyrics").font(.small)
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.mutedForeground)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
            .offset(y: lift)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open queue and lyrics")
        .accessibilityHint("Drag up to open Up next. Choose Lyrics inside the panel.")
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag in
                    guard abs(drag.translation.height) > abs(drag.translation.width) else { return }
                    lift = min(max(drag.translation.height * 0.2, -12), 12)
                }
                .onEnded { drag in
                    if abs(drag.translation.height) > abs(drag.translation.width) {
                        if drag.translation.height < -24 || drag.predictedEndTranslation.height < -60 { open() }
                        else if drag.translation.height > 60 || drag.predictedEndTranslation.height > 140 { minimize() }
                    }
                    withAnimation(Appearance.shared.animation(0.2)) { lift = 0 }
                }
        )
    }
}

/// The sheet behind those tabs: Up next and Lyrics, switchable without closing it.
struct NowPlayingPanel: View {
    enum Tab: String, CaseIterable, Identifiable {
        case queue, lyrics

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .queue: "list-music"
            case .lyrics: "mic-vocal"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .queue: "Up next"
            case .lyrics: "Lyrics"
            }
        }
    }

    @Namespace private var selectionIndicator
    @State var tab: Tab

    init(tab: Tab) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(Tab.allCases) { entry in
                    Button { withAnimation(Appearance.shared.animation(0.22)) { tab = entry } } label: {
                        Text(entry.title)
                            .font(.bodyStrong)
                            .foregroundStyle(tab == entry ? Theme.foreground : Theme.mutedForeground)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if tab == entry {
                                    Rectangle().fill(Theme.foreground).frame(height: 2)
                                        .matchedGeometryEffect(id: "panel-tab", in: selectionIndicator)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.inset)
            .padding(.top, 24)
            Hairline()

            ZStack {
                switch tab {
                case .queue: QueueView().transition(.opacity)
                case .lyrics: LyricsView().transition(.opacity)
                }
            }
        }
        .background(Theme.background)
    }
}
