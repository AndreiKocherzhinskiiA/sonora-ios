import CommonCrypto
import CryptoKit
import Foundation

/// Decryption helpers for Deezer's `BF_CBC_STRIPE` audio streams.
///
/// The stream is split into 2048-byte blocks and every third block (`index % 3 == 0`) is
/// Blowfish-CBC encrypted using a fixed IV and a per-track key derived from the MD5 hex of
/// the track ID plus a 16-byte master secret from Deezer's web player bundle.
nonisolated enum DeezerDecrypt {
    static let blockSize = 2048
    private static let stripe = 3
    private static let iv: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
    private static let webPlayerURL = URL(string: "https://www.deezer.com/en/channels/explore/")!
    private static let secretMD5 = "7ebf40da848f4a0fb3cc56ddbe6c2d09"
    static let fallbackSecret: [UInt8] = Array("g4el58wc0zvf9na1".utf8)

    static func trackKey(trackID: String, secret: [UInt8]) -> [UInt8] {
        let digest = Insecure.MD5.hash(data: Data(trackID.utf8))
        let hex = Array(digest.map { String(format: "%02x", $0) }.joined().utf8)
        guard hex.count == 32, secret.count == 16 else { return [UInt8](repeating: 0, count: 16) }
        var key = [UInt8](repeating: 0, count: 16)
        for index in 0..<16 {
            key[index] = hex[index] ^ hex[index + 16] ^ secret[index]
        }
        return key
    }

    /// Decrypts all complete 2048-byte encrypted stripes in `data`, assuming the first byte of
    /// `data` sits at `blockIndex * 2048` in the upstream audio object.
    static func decrypt(_ data: Data, startingAtBlock blockIndex: Int64, key: [UInt8]) -> Data {
        guard key.count == 16, data.count >= blockSize else { return data }
        var bytes = [UInt8](data)
        let wholeBlocks = bytes.count / blockSize
        for offsetBlock in 0..<wholeBlocks {
            let absoluteIndex = blockIndex + Int64(offsetBlock)
            guard absoluteIndex % Int64(stripe) == 0 else { continue }
            let start = offsetBlock * blockSize
            decryptBlock(&bytes[start..<(start + blockSize)], key: key)
        }
        return Data(bytes)
    }

    private static func decryptBlock(_ slice: inout ArraySlice<UInt8>, key: [UInt8]) {
        guard slice.count == blockSize else { return }
        var output = [UInt8](repeating: 0, count: blockSize)
        var outLength = 0
        let status: CCCryptorStatus = slice.withUnsafeBytes { input in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmBlowfish),
                0,
                key,
                key.count,
                iv,
                input.baseAddress,
                blockSize,
                &output,
                blockSize,
                &outLength
            )
        }
        if status == kCCSuccess, outLength == blockSize {
            slice.replaceSubrange(slice.startIndex..<slice.endIndex, with: output)
        }
    }

    /// Fetches the current master secret from Deezer's web player JS bundle and verifies its MD5,
    /// falling back to the last known secret if Deezer changes the bundle layout.
    static func fetchSecret(session: URLSession) async -> [UInt8] {
        do {
            let (pageData, _) = try await session.data(from: webPlayerURL)
            guard let html = String(data: pageData, encoding: .utf8),
                  let bundleURL = findBundle(in: html) else {
                return fallbackSecret
            }
            let (bundleData, _) = try await session.data(from: bundleURL)
            guard let source = String(data: bundleData, encoding: .utf8),
                  let first = findHalf(in: source, first: 0x61, last: 0x67),
                  let second = findHalf(in: source, first: 0x31, last: 0x34) else {
                return fallbackSecret
            }
            var secret = [UInt8](repeating: 0, count: 16)
            for index in 0..<8 {
                secret[index * 2] = first[index]
                secret[index * 2 + 1] = second[index]
            }
            let hash = Insecure.MD5.hash(data: Data(secret)).map { String(format: "%02x", $0) }.joined()
            guard hash == secretMD5 else { return fallbackSecret }
            return secret
        } catch {
            return fallbackSecret
        }
    }

    private static func findBundle(in html: String) -> URL? {
        var searchStart = html.startIndex
        while let at = html[searchStart...].range(of: "app-web")?.lowerBound {
            if let httpsRange = html[..<at].range(of: "https://", options: .backwards) {
                let start = httpsRange.lowerBound
                if let quote = html[start...].firstIndex(of: "\"") {
                    let candidate = String(html[start..<quote])
                    if candidate.hasSuffix(".js"), let url = URL(string: candidate) {
                        return url
                    }
                }
            }
            searchStart = html.index(at, offsetBy: min(7, html.distance(from: at, to: html.endIndex)))
        }
        return nil
    }

    private static func findHalf(in source: String, first: UInt8, last: UInt8) -> [UInt8]? {
        let needle = String(format: "0x%02x%%2C", first)
        let terminator = String(format: "0x%02x", last)
        var searchStart = source.startIndex
        while let range = source[searchStart...].range(of: needle) {
            if let bytes = parseHalf(String(source[range.lowerBound...].prefix(128)), terminator: terminator) {
                return bytes
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func parseHalf(_ candidate: String, terminator: String) -> [UInt8]? {
        guard let termRange = candidate.range(of: terminator) else { return nil }
        let segment = String(candidate[..<termRange.upperBound])
        guard segment.count <= 8 * "0xNN%2C".count else { return nil }
        var bytes: [UInt8] = []
        for part in segment.components(separatedBy: "%2C") {
            guard part.hasPrefix("0x"),
                  let value = UInt8(part.dropFirst(2), radix: 16) else { return nil }
            bytes.append(value)
        }
        guard bytes.count == 8 else { return nil }
        return bytes.reversed()
    }
}
