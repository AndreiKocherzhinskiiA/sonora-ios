import SwiftUI
import AVFoundation
import UIKit
import MediaPlayer
import Observation
import os

@Observable
final class PlaybackController {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var position: TimeInterval = 0
    /// The length of the current track: what its metadata said, then what the player reports once
    /// the stream is open, since a card on a shelf often carries none.
    private(set) var duration: TimeInterval = 0
    var repeatMode: RepeatMode = .off
    var isShuffled = false

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "playback")
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private weak var library: LocalLibrary?
    @ObservationIgnored private weak var youtube: YouTubeSession?
    @ObservationIgnored private weak var history: PlayHistory?
    @ObservationIgnored private var resolving: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var lengthTask: Task<Void, Never>?
    @ObservationIgnored private var artwork: UIImage?
    @ObservationIgnored private var radioToken: String?
    @ObservationIgnored private var radioClient: YouTubeClient?
    @ObservationIgnored private var radioLoading = false
    @ObservationIgnored private var isStartingRadio = false
    @ObservationIgnored private var artworkTrack: UUID?
    @ObservationIgnored private var artworkLoading: UUID?

    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var stalledSince: Date?
    @ObservationIgnored private var recordedTrack: UUID?

    init(offline: OfflineMusic) {
        self.offline = offline
        configureAudioSession()
        configureRemoteCommands()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    let wasPlaying = self.state == .playing
                    self.pause()
                    self.resumeAfterInterruption = wasPlaying
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let shouldResume = self.resumeAfterInterruption &&
                        AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if shouldResume {
                        do {
                            try AVAudioSession.sharedInstance().setActive(true)
                            self.resume()
                        } catch { self.state = .failed(error.localizedDescription) }
                    }
                }
            }
        }
    }

    func setLibrary(_ library: LocalLibrary) {
        self.library = library
    }

    /// Playback and the download UI share one store for the entire app lifetime.
    @ObservationIgnored private let offline: OfflineMusic

    func setHistory(_ history: PlayHistory) {
        self.history = history
    }

    /// Replaces the queue with a station seeded by `track` and plays it, then keeps it topped up
    /// from YouTube as the end of the queue nears.
    func startRadio(for track: Track, using client: YouTubeClient) async throws {
        guard case .youtube(let id) = track.source else { return }
        let (tracks, next) = try await client.radio(for: id)
        guard let first = tracks.first else { return }
        isStartingRadio = true
        play(first, from: tracks)
        isStartingRadio = false
        radioToken = next
        radioClient = client
    }

    private func topUpRadio() {
        guard let token = radioToken, let client = radioClient, !radioLoading,
              let current = currentTrack, let at = queue.firstIndex(where: { $0.id == current.id }),
              at >= queue.count - 3, case .youtube(let seed) = queue.first?.source ?? current.source else { return }
        radioLoading = true
        Task { @MainActor [weak self] in
            defer { self?.radioLoading = false }
            guard let more = try? await client.radio(for: seed, continuation: token) else { return }
            self?.queue += more.tracks
            self?.radioToken = more.next
        }
    }

    func setYouTube(_ youtube: YouTubeSession) {
        self.youtube = youtube
    }

    func play(_ track: Track, from tracks: [Track]? = nil) {
        if !isStartingRadio { radioToken = nil }
        let source = tracks ?? library?.tracks ?? [track]
        queue = isShuffled ? source.shuffled() : source
        guard queue.contains(where: { $0.id == track.id }) else {
            queue.insert(track, at: 0)
            load(track)
            return
        }
        load(track)
    }

    func togglePlayback() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .idle, .failed:
            if let currentTrack { load(currentTrack) }
            else if let first = queue.first ?? library?.tracks.first { play(first) }
        case .loading:
            break
        }
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil, state != .playing else { return }
        player.play()
        state = .playing
        updateNowPlaying()
    }

    func pause() {
        resumeAfterInterruption = false
        guard state == .playing else { return }
        player.pause()
        state = .paused
        updateNowPlaying()
    }

    func next() {
        guard let currentTrack,
              let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let nextIndex = queue.index(after: index)
        if nextIndex < queue.endIndex {
            load(queue[nextIndex])
        } else if repeatMode == .all, let first = queue.first {
            load(first)
        } else {
            stop()
        }
    }

    /// Goes back a song. With `restarting`, a song more than five seconds in starts over instead,
    /// as the button does; a swipe always moves to the song before.
    func previous(restarting: Bool = true) {
        if restarting, position > 5 {
            seek(to: 0)
            return
        }
        guard let currentTrack,
              let index = queue.firstIndex(where: { $0.id == currentTrack.id }),
              index > queue.startIndex else {
            seek(to: 0)
            return
        }
        load(queue[queue.index(before: index)])
    }

    func seek(to seconds: TimeInterval) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        position = max(0, seconds)
        updateNowPlaying()
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let currentTrack else {
            if isShuffled { queue.shuffle() }
            return
        }
        let remaining = queue.filter { $0.id != currentTrack.id }
        queue = [currentTrack] + (isShuffled ? remaining.shuffled() : remaining)
    }

    func advanceRepeatMode() {
        repeatMode.advance()
    }

    func dismissError() {
        if case .failed = state { state = .idle }
    }

    private func load(_ track: Track) {
        resumeAfterInterruption = false
        stalledSince = nil
        progressTask?.cancel()
        resolving?.cancel()
        state = .loading
        position = 0
        duration = track.duration
        currentTrack = track
        recordedTrack = nil
        topUpRadio()
        if let url = offline.localURL(for: track) {
            logger.notice("playing downloaded audio: \(url.lastPathComponent, privacy: .public)")
            start(AVPlayerItem(url: url))
            return
        }
        switch track.source {
        case .local, .stream:
            start(AVPlayerItem(url: track.sourceURL))
        case .youtube(let videoID):
            player.pause()
            resolving = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    guard let client = self.youtube?.client else { throw YouTubeError.signedOut }
                    let stream = try await client.stream(for: videoID)
                    guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
                    let asset = AVURLAsset(url: stream.url, options: [
                        "AVURLAssetHTTPHeaderFieldsKey": [
                            "User-Agent": stream.userAgent,
                            "Origin": "https://www.youtube.com",
                            "Referer": "https://www.youtube.com/",
                        ],
                    ])
                    if self.duration <= 0, let length = stream.duration, length > 0 { self.duration = length }
                    self.start(AVPlayerItem(asset: asset))
                } catch is CancellationError {
                    return
                } catch {
                    guard self.currentTrack?.id == track.id else { return }
                    self.logger.error("cannot play the youtube track: \(error.localizedDescription, privacy: .public)")
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func start(_ item: AVPlayerItem) {
        observeEnd(of: item)
        lengthTask?.cancel()
        lengthTask = Task { @MainActor [weak self, weak item] in
            guard let item, let length = try? await item.asset.load(.duration).seconds,
                  length.isFinite, length > 0, !Task.isCancelled,
                  self?.player.currentItem === item, let self else { return }
            // What the service said about the track wins. The player's own reading only fills
            // in a length nobody gave, because a streamed fragmented file can report it wrong.
            if self.duration <= 0 {
                self.duration = length
                self.updateNowPlaying()
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        state = .playing
        startProgressUpdates()
        updateNowPlaying()
    }

    /// Moves on when `item` plays to its end, which works for a track whose length was never known.
    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.trackEnded() }
        }
    }

    /// Repeats or moves on once the current track is over, whether the player or the clock said so.
    private func trackEnded() {
        if repeatMode == .one, let track = currentTrack {
            load(track)
        } else {
            next()
        }
    }

    /// Jumps `seconds` ahead (or back when negative). Past the end of a track of known length it
    /// moves on instead.
    func skip(by seconds: TimeInterval) {
        guard currentTrack != nil, state == .playing || state == .paused else { return }
        let target = position + seconds
        if duration > 0, target >= duration {
            trackEnded()
        } else {
            seek(to: target)
        }
    }

    /// Puts `track` right after the playing one.
    func playNext(_ track: Track) {
        guard currentTrack != nil else { play(track, from: [track]); return }
        let copy = Track(copying: track)
        let at = currentTrack.flatMap { current in queue.firstIndex { $0.id == current.id } }.map { $0 + 1 } ?? queue.endIndex
        queue.insert(copy, at: min(at, queue.endIndex))
    }

    /// Puts `track` at the end of the queue.
    func playLast(_ track: Track) {
        guard currentTrack != nil else { play(track, from: [track]); return }
        queue.append(Track(copying: track))
    }

    /// Plays `track`, which has to be in the queue.
    func jump(to track: Track) {
        guard queue.contains(where: { $0.id == track.id }) else { return }
        load(track)
    }

    /// Takes a track out of the queue. The playing track stays.
    func removeFromQueue(_ track: Track) {
        guard track.id != currentTrack?.id else { return }
        queue.removeAll { $0.id == track.id }
    }

    /// Reorders queue entries without replacing the playing item.
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
    }

    private func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
        position = 0
        duration = 0
        state = .idle
        progressTask?.cancel()
        resolving?.cancel()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                guard !Task.isCancelled else { return }
                if self.player.currentItem?.status == .failed {
                    self.player.pause()
                    self.state = .failed(self.player.currentItem?.error?.localizedDescription ?? String(localized: "Audio playback failed."))
                    self.updateNowPlaying()
                    return
                }
                if self.state == .playing, self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    if self.stalledSince == nil { self.stalledSince = Date() }
                    if let since = self.stalledSince, Date().timeIntervalSince(since) > 30 {
                        self.player.pause()
                        self.state = .failed(String(localized: "Playback timed out. Please try again."))
                        self.updateNowPlaying()
                        return
                    }
                } else { self.stalledSince = nil }
                if self.player.timeControlStatus == .playing,
                   let track = self.currentTrack, self.recordedTrack != track.id {
                    self.recordedTrack = track.id
                    self.history?.record(track)
                }
                self.position = self.player.currentTime().seconds.finiteOrZero
                // A streamed file can run well past the length the service gave, so the player
                // never reports an end; the known length is the end.
                if self.state == .playing, self.duration > 0, self.position >= self.duration {
                    self.trackEnded()
                    continue
                }
                self.updateNowPlaying()
            }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            logger.error("cannot configure audio session: \(error.localizedDescription, privacy: .public)")
            state = .failed(String(localized: "Audio playback is unavailable."))
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artists,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork, artworkTrack == track.id {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = switch state {
        case .playing: .playing
        case .paused: .paused
        case .idle, .failed: .stopped
        case .loading: .interrupted
        }
        loadArtworkIfNeeded(for: track)
    }

    /// Fetches the cover once per track so the lock screen and the Dynamic Island can show it.
    private func loadArtworkIfNeeded(for track: Track) {
        guard artworkTrack != track.id, artworkLoading != track.id, let url = track.artworkURL else { return }
        artworkLoading = track.id
        Task { @MainActor [weak self] in
            let image = await Self.image(at: url)
            guard let self, self.currentTrack?.id == track.id else { return }
            self.artworkLoading = nil
            guard let image else { return }
            self.artwork = image
            self.artworkTrack = track.id
            self.updateNowPlaying()
        }
    }

    private static func image(at url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

private extension Double {
    var finiteOrZero: Double { isFinite ? self : 0 }
}

