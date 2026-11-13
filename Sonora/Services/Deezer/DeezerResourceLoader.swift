import AVFoundation
import Foundation
import os

/// Streams and incrementally decrypts `BF_CBC_STRIPE` Deezer audio for `AVPlayer` over custom
/// `sonora-deezer://` URLs by aligning byte-range requests to 2048-byte Blowfish boundaries.
final class DeezerResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "sonora-deezer"

    static func assetURL(for trackID: String) -> URL {
        URL(string: "\(scheme)://track/\(trackID)")!
    }

    let queue = DispatchQueue(label: "org.sonorahq.sonora.deezer-loader")

    private let stream: DeezerStream
    private let session: URLSession
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var totalLength: Int64?
        var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    }

    init(stream: DeezerStream) {
        self.stream = stream
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
        super.init()
    }

    deinit {
        let tasks = stateLock.withLock { state -> [Task<Void, Never>] in
            let active = Array(state.tasks.values)
            state.tasks.removeAll()
            return active
        }
        for task in tasks { task.cancel() }
        session.invalidateAndCancel()
    }

    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let key = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self, loadingRequest] in
            guard let self else {
                loadingRequest.finishLoading(with: URLError(.cancelled))
                return
            }
            defer {
                _ = self.stateLock.withLock { $0.tasks.removeValue(forKey: key) }
            }
            do {
                try await self.handle(loadingRequest)
                if !Task.isCancelled {
                    loadingRequest.finishLoading()
                }
            } catch is CancellationError {
                loadingRequest.finishLoading(with: URLError(.cancelled))
            } catch {
                loadingRequest.finishLoading(with: error)
            }
        }
        stateLock.withLock { $0.tasks[key] = task }
        return true
    }

    nonisolated func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        let task = stateLock.withLock { $0.tasks.removeValue(forKey: key) }
        task?.cancel()
    }

    private nonisolated func handle(_ loadingRequest: AVAssetResourceLoadingRequest) async throws {
        let total = try await resolveContentLength()

        if let info = loadingRequest.contentInformationRequest {
            info.isByteRangeAccessSupported = true
            info.contentType = stream.contentType
            info.contentLength = total
        }

        guard let dataRequest = loadingRequest.dataRequest else { return }

        let blockSize = Int64(DeezerDecrypt.blockSize)
        var cursor = dataRequest.currentOffset > 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let endTarget: Int64
        if dataRequest.requestsAllDataToEndOfResource {
            endTarget = total
        } else {
            endTarget = min(total, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
        }

        let maxChunkBytes: Int64 = 131_072 // 64 * 2048 bytes
        while cursor < endTarget {
            try Task.checkCancellation()
            let requestEnd = min(endTarget, cursor + maxChunkBytes)
            let alignedStart = (cursor / blockSize) * blockSize
            let alignedEnd = min(total - 1, (((requestEnd - 1) / blockSize) + 1) * blockSize - 1)

            let encrypted = try await fetchRange(start: alignedStart, endInclusive: alignedEnd)
            let decrypted = DeezerDecrypt.decrypt(encrypted, startingAtBlock: alignedStart / blockSize, key: stream.key)

            let sliceOffset = Int(cursor - alignedStart)
            let available = decrypted.count - sliceOffset
            guard available > 0 else { break }
            let needed = min(available, Int(requestEnd - cursor))
            let slice = decrypted.subdata(in: sliceOffset..<(sliceOffset + needed))
            dataRequest.respond(with: slice)
            cursor += Int64(slice.count)
        }
    }

    private nonisolated func resolveContentLength() async throws -> Int64 {
        if let cached = stateLock.withLock({ $0.totalLength }) {
            return cached
        }
        var request = URLRequest(url: stream.url, timeoutInterval: 20)
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let length = parseTotalLength(from: http) else {
            throw DeezerError.badResponse
        }
        stateLock.withLock { $0.totalLength = length }
        return length
    }

    private nonisolated func fetchRange(start: Int64, endInclusive: Int64) async throws -> Data {
        var request = URLRequest(url: stream.url, timeoutInterval: 30)
        request.setValue("bytes=\(start)-\(endInclusive)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty else {
            throw DeezerError.badResponse
        }
        if let total = parseTotalLength(from: http) {
            stateLock.withLock { $0.totalLength = total }
        }
        return data
    }

    private nonisolated func parseTotalLength(from response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let totalPart = range.split(separator: "/").last,
           let total = Int64(totalPart), total > 0 {
            return total
        }
        if response.statusCode == 200,
           let lengthText = response.value(forHTTPHeaderField: "Content-Length"),
           let total = Int64(lengthText), total > 0 {
            return total
        }
        return nil
    }
}
