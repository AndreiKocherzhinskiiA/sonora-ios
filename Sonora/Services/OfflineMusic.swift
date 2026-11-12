import Foundation
import Observation
#if canImport(Network)
import Network
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Downloads audio in bounded ranges. Committed chunks and the queue survive interruption/relaunch.
@Observable
final class OfflineMusic {
    struct Job: Codable, Identifiable {
        let track: Track
        var received: Int64 = 0
        var total: Int64?
        var format: String?
        var id: UUID { track.id }
        var fraction: Double? { total.flatMap { $0 > 0 ? min(Double(received) / Double($0), 1) : nil } }
    }

    private(set) var tracks: [Track] = []
    private(set) var jobs: [Job] = []
    private(set) var downloading = Set<Track.Source>()
    private(set) var isPaused = false
    private(set) var isConnected = false
    var failure: String?
    var smartDownloads = UserDefaults.standard.bool(forKey: "smartDownloads") {
        didSet {
            UserDefaults.standard.set(smartDownloads, forKey: "smartDownloads")
            if !smartDownloads { smartDownloadsRunning = false }
        }
    }
    private(set) var smartDownloadsRunning = UserDefaults.standard.bool(forKey: "smartDownloadsRunning") {
        didSet { UserDefaults.standard.set(smartDownloadsRunning, forKey: "smartDownloadsRunning") }
    }
    private(set) var appliedSmartDownloadLimit: Int = {
        let saved = UserDefaults.standard.integer(forKey: "appliedSmartDownloadLimit")
        return saved == 0 ? 20 : min(max(saved, 10), 500)
    }()
    static let smartDownloadRange = 10...500
    private var configuredSmartLimit: Int = {
        let saved = UserDefaults.standard.integer(forKey: "smartDownloadLimit")
        return saved == 0 ? 20 : min(max(saved, 10), 500)
    }()

    var smartDownloadLimit: Int {
        get { configuredSmartLimit }
        set {
            configuredSmartLimit = min(max(newValue, Self.smartDownloadRange.lowerBound), Self.smartDownloadRange.upperBound)
            UserDefaults.standard.set(configuredSmartLimit, forKey: "smartDownloadLimit")
        }
    }

    /// Count distinct downloadable songs, so repeat listens do not consume the configured limit.
    func smartTracks(from history: [Track], limit: Int? = nil) -> [Track] {
        var seen = Set<Track.Source>()
        var result: [Track] = []
        for track in history {
            guard case .youtube = track.source, seen.insert(track.source).inserted else { continue }
            result.append(track)
            if result.count == (limit ?? smartDownloadLimit) { break }
        }
        return result
    }

    /// Slider edits are drafts. Only this explicit action applies the new limit and starts work.
    func startSmartDownloads(from history: [Track], using client: YouTubeClient) async {
        guard smartDownloads else { return }
        appliedSmartDownloadLimit = smartDownloadLimit
        UserDefaults.standard.set(appliedSmartDownloadLimit, forKey: "appliedSmartDownloadLimit")
        smartDownloadsRunning = true
        await download(smartTracks(from: history, limit: appliedSmartDownloadLimit), using: client)
        resume(using: client)
    }

    /// Cancels active/queued work and future smart refills until Start downloads is pressed again.
    /// Completed audio is retained; only partial files belonging to cancelled jobs are removed.
    func cancelAllDownloads() {
        pause()
        smartDownloadsRunning = false
        let cancelled = jobs
        do {
            try prepareFolder()
            try JSONEncoder().encode([Job]()).write(to: pending, options: .atomic)
            jobs = []
            isPaused = false
            failure = nil
            for job in cancelled {
                let url = part(for: job.track)
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch { failure = error.localizedDescription }
    }

    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private weak var client: YouTubeClient?
    @ObservationIgnored private var waitingForConnection = false
    #if canImport(Network)
    @ObservationIgnored private let network = NWPathMonitor()
    #endif
    private let folder = URL.applicationSupportDirectory.appending(path: "Sonora/Downloads", directoryHint: .isDirectory)
    private var manifest: URL { folder.appending(path: "index.json") }
    private var pending: URL { folder.appending(path: "pending.json") }

    init() {
        do {
            if FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)) {
                tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: manifest))
                    .filter { size(of: file(for: $0)) > 0 }
            }
            if FileManager.default.fileExists(atPath: pending.path(percentEncoded: false)) {
                jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: pending))
                    .filter { job in !tracks.contains { $0.source == job.track.source } }
                for index in jobs.indices { jobs[index].received = size(of: part(for: jobs[index].track)) }
                // Finish locally before asking the provider for any URL, even in airplane mode.
                for job in jobs {
                    if let total = job.total, total > 0,
                       size(of: file(for: job.track)) == total || size(of: part(for: job.track)) == total {
                        try finish(job)
                    }
                }
            }
        } catch { failure = error.localizedDescription }
        isPaused = !jobs.isEmpty
        #if canImport(Network)
        network.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.connectionChanged(isConnected: connected) }
        }
        network.start(queue: DispatchQueue(label: "org.sonorahq.sonora.download-network"))
        #endif
    }

    /// Network loss suspends transfers without turning an expected offline state into a failure.
    func connectionChanged(isConnected: Bool) {
        self.isConnected = isConnected
        if !isConnected, worker != nil {
            pause()
            waitingForConnection = true
        } else if isConnected, waitingForConnection, let client {
            resume(using: client)
        }
    }

    /// Recovers published files whose metadata save was interrupted, using known song metadata.
    func recover(_ songs: [Track]) {
        do {
            var recovered = tracks
            for track in songs where !recovered.contains(where: { $0.source == track.source }) {
                guard case .youtube = track.source, size(of: file(for: track)) > 0 else { continue }
                recovered.append(track)
            }
            guard recovered.count != tracks.count else { return }
            try prepareFolder()
            try JSONEncoder().encode(recovered).write(to: manifest, options: .atomic)
            tracks = recovered
            jobs.removeAll { job in tracks.contains { $0.source == job.track.source } }
            try saveJobs()
            isPaused = !jobs.isEmpty
        } catch { failure = error.localizedDescription }
    }

    private func file(for track: Track) -> URL { folder.appending(path: "\(track.id).m4a") }
    private func part(for track: Track) -> URL { folder.appending(path: "\(track.id).partial") }
    private func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    func localURL(for track: Track) -> URL? {
        guard let saved = tracks.first(where: { $0.source == track.source }) else { return nil }
        let url = file(for: saved)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func job(for track: Track) -> Job? { jobs.first { $0.track.source == track.source } }

    /// Enqueues work independently of the presenting view or smart-history task's lifetime.
    func download(_ songs: [Track], using client: YouTubeClient) async {
        do {
            try prepareFolder()
            recover(songs)
            for track in songs {
                guard case .youtube = track.source, localURL(for: track) == nil, job(for: track) == nil else { continue }
                jobs.append(Job(track: track))
            }
            try saveJobs()
            if !isPaused { resume(using: client) }
        } catch { failure = error.localizedDescription }
    }

    /// Stops at the last committed chunk; a cancelled in-flight chunk alone must be fetched again.
    func pause() {
        waitingForConnection = false
        generation = UUID()
        worker?.cancel()
        worker = nil
        downloading = []
        isPaused = !jobs.isEmpty
    }

    func resume(using client: YouTubeClient) {
        self.client = client
        guard worker == nil, !jobs.isEmpty else { return }
        guard isConnected else {
            waitingForConnection = true
            isPaused = true
            return
        }
        waitingForConnection = false
        failure = nil
        isPaused = false
        let token = UUID()
        generation = token
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token {
                    self.worker = nil
                    self.downloading = []
                }
            }
            while !self.jobs.isEmpty, !Task.isCancelled {
                let job = self.jobs[0]
                self.downloading = [job.track.source]
                do {
                    try await self.transfer(job, using: client)
                    try Task.checkCancellation()
                } catch {
                    guard self.generation == token else { return }
                    self.isPaused = true
                    let networkError = error as? URLError
                    let offlineCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff]
                    if let networkError, offlineCodes.contains(networkError.code) {
                        self.waitingForConnection = true
                        self.failure = nil
                    } else if !(error is CancellationError) {
                        self.failure = error.localizedDescription
                    }
                    return
                }
            }
        }
    }

    /// Re-resolves expiring URLs and appends only a matching byte range of the same audio format.
    private func transfer(_ job: Job, using client: YouTubeClient) async throws {
        guard case .youtube(let id) = job.track.source else { return }
        let partial = part(for: job.track)
        var offset = size(of: partial)
        if let total = job.total, offset == total {
            try finish(job)
            return
        }
        let stream = try await client.stream(for: id)
        try Task.checkCancellation()
        let query = URLComponents(url: stream.url, resolvingAgainstBaseURL: false)?.queryItems
        let format = query?.first { $0.name == "itag" }?.value
        let expectedLength = stream.contentLength ?? query?.first { $0.name == "clen" }?.value.flatMap(Int64.init)
        if job.received > 0, job.format != format {
            throw DownloadError.changed
        }
        while !Task.isCancelled {
            var request = URLRequest(url: stream.url, timeoutInterval: 30)
            request.setValue("bytes=\(offset)-\(offset + 131_071)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue(stream.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, !data.isEmpty else { throw YouTubeError.refused }
            let total: Int64
            if http.statusCode == 206 || (http.statusCode == 200 && http.value(forHTTPHeaderField: "Content-Range") != nil) {
                guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                      range.hasPrefix("bytes \(offset)-"),
                      let length = Int64(range.split(separator: "/").last ?? ""), length > 0,
                      let endText = range.split(separator: "/").first?.split(separator: "-").last,
                      let end = Int64(endText), end - offset + 1 == Int64(data.count) else {
                    throw DownloadError.invalidRange
                }
                total = length
            } else if http.statusCode == 200, offset == 0 {
                // Do not mark a short HTTP 200 response as a complete song.
                guard expectedLength == nil || expectedLength == Int64(data.count) else { throw DownloadError.invalidRange }
                total = Int64(data.count)
            } else {
                // Never append a full response or an error page to an existing partial file.
                throw DownloadError.invalidRange
            }
            if let expectedLength, expectedLength != total { throw DownloadError.changed }
            if let expected = jobs.first?.total, expected != total { throw DownloadError.changed }
            guard offset + Int64(data.count) <= total else { throw DownloadError.invalidRange }
            guard let current = jobs.firstIndex(where: { $0.id == job.id }) else { return }
            jobs[current].total = total
            jobs[current].format = format
            try saveJobs()
            if offset == 0 { try data.write(to: partial, options: .atomic) }
            else {
                let handle = try FileHandle(forWritingTo: partial)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.synchronize()
            }
            offset += Int64(data.count)
            guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
            jobs[index].received = offset
            jobs[index].total = total
            jobs[index].format = format
            try saveJobs()
            if offset == total {
                try finish(job)
                return
            }
        }
        throw CancellationError()
    }

    /// Atomic publication replaces stale destinations and is safe to repeat after interruption.
    private func finish(_ job: Job) throws {
        let partial = part(for: job.track)
        let destination = file(for: job.track)
        let expected = jobs.first(where: { $0.id == job.id })?.total ?? job.total
        guard let expected, expected > 0 else { throw DownloadError.invalidRange }
        if size(of: destination) != expected {
            guard size(of: partial) == expected else { throw DownloadError.invalidRange }
            // POSIX rename atomically replaces a destination; no remove/copy race or duplicate file error.
            let result = partial.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    rename(source!, target!)
                }
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        if !tracks.contains(where: { $0.source == job.track.source }) {
            let updated = tracks + [job.track]
            try JSONEncoder().encode(updated).write(to: manifest, options: .atomic)
            tracks = updated
        }
        jobs.removeAll { $0.id == job.id }
        try saveJobs()
        try? FileManager.default.removeItem(at: partial)
    }

    private func prepareFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directory = folder
        try directory.setResourceValues(excluded)
    }

    private func saveJobs() throws { try JSONEncoder().encode(jobs).write(to: pending, options: .atomic) }

    func discard(_ job: Job) {
        pause()
        do {
            jobs.removeAll { $0.id == job.id }
            try saveJobs()
            try? FileManager.default.removeItem(at: part(for: job.track))
            isPaused = !jobs.isEmpty
        } catch { failure = error.localizedDescription }
    }

    func remove(_ track: Track) {
        do {
            let updated = tracks.filter { $0.id != track.id }
            try JSONEncoder().encode(updated).write(to: manifest, options: .atomic)
            tracks = updated
            try FileManager.default.removeItem(at: file(for: track))
        } catch { failure = error.localizedDescription }
    }
}

private enum DownloadError: LocalizedError {
    case changed, invalidRange
    var errorDescription: String? {
        switch self {
        case .changed: String(localized: "The audio file changed. Remove this pending download and download it again.")
        case .invalidRange: String(localized: "The server could not resume this download. Your saved progress has been kept. Try again.")
        }
    }
}
