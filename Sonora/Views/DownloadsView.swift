import SwiftUI

/// Download management uses the app's existing rows, surfaces, and reduced-motion preferences.
struct DownloadsView: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(PlayHistory.self) private var history
    @Environment(PlaybackController.self) private var playback
    @Environment(YouTubeSession.self) private var youtube
    @State private var showsSmartSettings = false

    var body: some View {
        List {
            smartSettings
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if !offline.jobs.isEmpty {
                Section {
                    HStack {
                        Text(offline.isPaused ? "Paused" : "Downloading").font(.largeText)
                        Spacer()
                        Button {
                            if offline.isPaused, let client = youtube.client { offline.resume(using: client) }
                            else { offline.pause() }
                        } label: {
                            Text(offline.isPaused ? "Resume" : "Pause").font(.bodyStrong)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(offline.isPaused && youtube.client == nil)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    Button("Cancel all downloads", role: .destructive) { offline.cancelAllDownloads() }
                        .font(.bodyStrong).foregroundStyle(Theme.danger)
                        .frame(minHeight: 44)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(offline.jobs) { job in
                        DownloadJobRow(job: job)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            if let failure = offline.failure {
                Text(failure).font(.small).foregroundStyle(Theme.danger)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if offline.tracks.isEmpty && offline.jobs.isEmpty {
                Vacancy(icon: "music", title: "Your offline music",
                        message: "Download a song from its menu, or save a playlist from its page. Your songs will appear here.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if !offline.tracks.isEmpty {
                Section {
                    ForEach(offline.tracks) { track in
                        TrackRow(track: track) {
                            playback.play(track, from: offline.tracks)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Downloaded").font(.largeText).foregroundStyle(Theme.foreground)
                        .textCase(nil).padding(.vertical, 8)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
    }

    @ViewBuilder
    private var smartSettings: some View {
        @Bindable var offline = offline
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Smart downloads", isOn: $offline.smartDownloads)
                .font(.bodyStrong).tint(Theme.primary)
            Text("Choose up to \(offline.smartDownloadLimit) recent songs, then tap Start downloads. Changing the slider does not start downloads. Downloads may use cellular data.")
                .font(.small).foregroundStyle(Theme.mutedForeground)
            DisclosureGroup("Smart download settings", isExpanded: $showsSmartSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Song limit").font(.bodyStrong)
                        Spacer()
                        Text("\(offline.smartDownloadLimit) songs").font(.small.monospacedDigit())
                    }
                    Slider(value: Binding(
                        get: { Double(offline.smartDownloadLimit) },
                        set: { offline.smartDownloadLimit = Int($0) }
                    ), in: Double(OfflineMusic.smartDownloadRange.lowerBound)...Double(OfflineMusic.smartDownloadRange.upperBound), step: 10)
                    .tint(Theme.primary)
                    .accessibilityLabel("Smart download song limit")
                    .accessibilityValue("\(offline.smartDownloadLimit) songs")
                    HStack {
                        Text("10")
                        Spacer()
                        Text("500")
                    }
                    .font(.small.monospacedDigit()).foregroundStyle(Theme.mutedForeground)
                }
                .padding(.top, 12)
            }
            .font(.small).tint(Theme.foreground)
            Button("Start downloads") {
                guard let client = youtube.client else { return }
                Task { await offline.startSmartDownloads(from: history.tracks, using: client) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!offline.smartDownloads || youtube.client == nil || offline.smartTracks(from: history.tracks).isEmpty)
            .padding(.top, 8)
        }
        .animation(Appearance.shared.animation(0.2), value: showsSmartSettings)
        .padding(16)
        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: Theme.radius))
        .padding(.horizontal, Theme.inset)
    }

}

private struct DownloadJobRow: View {
    @Environment(OfflineMusic.self) private var offline
    let job: OfflineMusic.Job

    private var active: Bool { offline.downloading.contains(job.track.source) }
    private var bytes: String {
        let received = ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file)
        guard let total = job.total else { return received }
        return "\(received) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: job.track.artworkURL, size: Theme.thumb)
            VStack(alignment: .leading, spacing: 6) {
                Text(job.track.title).font(.bodyStrong).lineLimit(1)
                HStack {
                    Text(offline.isPaused ? "Paused" : active ? "Downloading" : "Queued")
                    Spacer()
                    if let fraction = job.fraction { Text(fraction, format: .percent.precision(.fractionLength(0))) }
                }
                .font(.small).foregroundStyle(Theme.mutedForeground)
                ProgressView(value: job.fraction ?? 0)
                    .tint(Theme.foreground)
                    .animation(Appearance.shared.animation(0.2), value: job.received)
                    .accessibilityLabel("Download progress")
                Text(bytes).font(.small.monospacedDigit()).foregroundStyle(Theme.mutedForeground)
            }
            Menu {
                Button("Remove download", role: .destructive) { offline.discard(job) }
            } label: {
                Icon("ellipsis", size: 18).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Download options for \(job.track.title)")
        }
        .padding(.horizontal, Theme.inset).padding(.vertical, 8)
    }
}

/// Collection actions stay visible with a count and link to transfer details.
struct CollectionDownloadControl: View {
    @Environment(OfflineMusic.self) private var offline
    @Environment(YouTubeSession.self) private var youtube
    let tracks: [Track]

    private var saved: Int { tracks.filter { offline.localURL(for: $0) != nil }.count }
    private var queued: Bool { tracks.contains { offline.job(for: $0) != nil } }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard let client = youtube.client else { return }
                Task { await offline.download(tracks, using: client) }
            } label: {
                Label(saved == tracks.count ? "Downloaded" : queued ? "Queued" : "Download", systemImage: saved == tracks.count ? "checkmark.circle" : "arrow.down.circle")
                    .font(.bodyStrong).frame(minHeight: 44)
            }
            .disabled(youtube.client == nil || queued || saved == tracks.count)
            Spacer()
            NavigationLink {
                DownloadsView().navigationTitle("Offline music")
            } label: {
                Text("\(saved) / \(tracks.count)").font(.small.monospacedDigit())
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Manage downloads, \(saved) of \(tracks.count) saved")
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, Theme.inset)
        .animation(Appearance.shared.animation(0.2), value: saved)
    }
}
