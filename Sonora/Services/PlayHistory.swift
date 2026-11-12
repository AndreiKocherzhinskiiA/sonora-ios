import Foundation
import Observation
import os

/// The songs that have played, newest first, kept on this iPhone. The phone form of the desktop
/// listening history.
@Observable
final class PlayHistory {
    private(set) var tracks: [Track] = []

    @ObservationIgnored private let limit = 500
    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "history")
    @ObservationIgnored private var url: URL {
        URL.applicationSupportDirectory.appending(path: "Sonora", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    func restore() {
        guard let data = try? Data(contentsOf: url) else { return }
        tracks = (try? JSONDecoder().decode([Track].self, from: data)) ?? []
    }

    /// Notes that `track` started playing. Playing the same song twice in a row counts once.
    func record(_ track: Track) {
        if let last = tracks.first, last.title == track.title, last.artists == track.artists { return }
        tracks.insert(Track(copying: track), at: 0)
        if tracks.count > limit { tracks.removeLast(tracks.count - limit) }
        save()
    }

    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        save()
    }

    func clear() {
        tracks = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(tracks).write(to: url, options: .atomic)
        } catch {
            logger.error("cannot save the history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
