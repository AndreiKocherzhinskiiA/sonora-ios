import SwiftUI

/// The play queue: what is playing, then what comes after. Tapping a row jumps to it, and
/// swiping a row left removes it.
struct QueueView: View {
    @Environment(PlaybackController.self) private var playback
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(spacing: 0) {
            if playback.queue.isEmpty {
                Vacancy(icon: "list-music", title: "The queue is empty")
            } else {
                HStack {
                    Text("\(playback.queue.count) songs").font(.small).foregroundStyle(Theme.mutedForeground)
                    Spacer()
                    Button(editMode == .active ? "Done" : "Reorder") {
                        withAnimation(Appearance.shared.animation(0.2)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .font(.bodyStrong)
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Reorder with the drag handles. Drag song rows to scroll.")
                }
                .padding(.horizontal, Theme.inset)
                ScrollViewReader { proxy in
                    List {
                        ForEach(playback.queue) { track in
                            TrackRow(track: track, inQueue: true) { playback.jump(to: track) }
                                .moveDisabled(editMode != .active)
                                .id(track.id)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing) {
                                    if track.id != playback.currentTrack?.id {
                                        Button("Remove", role: .destructive) { playback.removeFromQueue(track) }
                                            .tint(Theme.danger)
                                    }
                                }
                        }
                        .onMove { playback.moveQueue(from: $0, to: $1) }
                    }
                    .environment(\.editMode, $editMode)
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        if let id = playback.currentTrack?.id { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .background(Theme.background)
    }
}
