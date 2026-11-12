import Foundation
import Observation
import os

/// One synced line.
struct LyricLine: Identifiable, Equatable {
    let id: Int
    let start: TimeInterval
    let text: String
}

/// What lyrics a track has, if any.
enum LyricsContent: Equatable {
    case synced([LyricLine])
    case plain(String)
}

/// Reads `[mm:ss.xx] text` sheets, the Swift form of `lyrics::lrc::parse` for line timing.
enum LRC {
    /// Lines in time order. A line with several stamps appears once per stamp, and tags such as
    /// `[ar:Name]` and the word timings inside `<...>` are skipped.
    static func parse(_ sheet: String) -> [LyricLine] {
        var found: [(TimeInterval, String)] = []
        for raw in sheet.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var stamps: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let seconds = stamp(inside) { stamps.append(seconds) }
            }
            guard !stamps.isEmpty else { continue }
            let text = strippingWordTimes(String(rest)).trimmingCharacters(in: .whitespaces)
            for start in stamps { found.append((start, text)) }
        }
        return found.sorted { $0.0 < $1.0 }.enumerated().map {
            LyricLine(id: $0.offset, start: $0.element.0, text: $0.element.1)
        }
    }

    private static func stamp(_ text: Substring) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }

    private static func strippingWordTimes(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\d+:\d+(?:\.\d+)?>"#, with: "", options: .regularExpression)
    }
}

/// Finds lyrics for the playing track: LRCLIB for synced lyrics, then YouTube Music's own sheet for
/// a YouTube track. Results are kept per track, so reopening the panel never asks again.
@Observable
final class LyricsService {
    enum State: Equatable {
        case idle
        case loading
        case found(LyricsContent, source: String)
        case missing
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var cache: [String: State] = [:]
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "lyrics")

    /// Looks lyrics up for `track`. `length` is its duration, which picks between versions of a song.
    func load(for track: Track, length: TimeInterval, youtube: YouTubeClient?) async {
        let key = "\(track.title)|\(track.artists)"
        if let kept = cache[key] {
            state = kept
            return
        }
        state = .loading
        var failure: String?

        do {
            if let hit = try await lrclib(track, length: length) {
                return finish(key, .found(hit, source: "LrcLib"))
            }
        } catch {
            logger.error("lrclib failed: \(error.localizedDescription, privacy: .public)")
            failure = error.localizedDescription
        }

        if case .youtube(let id) = track.source, let youtube {
            do {
                if let text = try await youtube.lyrics(for: id) {
                    return finish(key, .found(.plain(text), source: "YouTube Music"))
                }
            } catch {
                logger.error("youtube lyrics failed: \(error.localizedDescription, privacy: .public)")
                failure = failure ?? error.localizedDescription
            }
        }

        if Task.isCancelled { return }
        finish(key, failure.map { .failed($0) } ?? .missing, remember: failure == nil)
    }

    private func finish(_ key: String, _ result: State, remember: Bool = true) {
        if remember { cache[key] = result }
        state = result
    }

    // MARK: LRCLIB

    private struct Found: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
    }

    private func lrclib(_ track: Track, length: TimeInterval) async throws -> LyricsContent? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        let artist = track.artistReferences.first?.name ?? track.artists
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("sonora-ios/0.1.0 (https://github.com/sonorahq/sonora)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw YouTubeError.http("lrclib", status)
        }
        let found = try JSONDecoder().decode([Found].self, from: data)

        let closeness: (Found) -> Double = { hit in
            guard length > 0, let seconds = hit.duration else { return 0 }
            return abs(seconds - length)
        }
        let synced = found
            .filter { !($0.syncedLyrics ?? "").isEmpty }
            .sorted { closeness($0) < closeness($1) }
        for hit in synced {
            let lines = LRC.parse(hit.syncedLyrics ?? "")
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = found.compactMap({ $0.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return .plain(plain)
        }
        return nil
    }
}
