import CryptoKit
import Foundation
import Observation
import Security
import os

/// The signed-in Subsonic / Navidrome server account: URL, username, and salted MD5 signature
/// persisted in the keychain, plus the client built from them.
@Observable
final class SubsonicSession {
    struct Credentials: Codable, Sendable {
        let server: String
        let username: String
        let salt: String
        let token: String
    }

    private(set) var isSignedIn = false
    private(set) var serverDisplayName: String?
    private(set) var client: SubsonicClient?

    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "subsonic")
    @ObservationIgnored private let account = "subsonic-credentials"
    @ObservationIgnored private let service = "org.sonorahq.sonora"

    /// Restores a saved server session from the keychain, if present.
    func restore() {
        guard let credentials = readKeychain() else { return }
        adopt(credentials)
    }

    /// Normalizes `server`, computes an OpenSubsonic salted MD5 token, verifies connectivity via
    /// `/rest/ping.view`, and stores the resulting credentials in the keychain.
    func signIn(server rawServer: String, username rawUsername: String, password: String) async throws {
        let serverURL = try Self.normalizeServer(rawServer)
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { throw SubsonicError.invalidInput(String(localized: "Enter a username.")) }
        guard !password.isEmpty else { throw SubsonicError.invalidInput(String(localized: "Enter a password.")) }

        let salt = Self.makeSalt()
        let token = Self.md5Hex(password + salt)
        let credentials = Credentials(
            server: serverURL.absoluteString,
            username: username,
            salt: salt,
            token: token
        )
        let candidate = try SubsonicClient(credentials: credentials)
        try await candidate.ping()
        writeKeychain(credentials)
        adopt(credentials, client: candidate)
    }

    func signOut() {
        deleteKeychain()
        client = nil
        serverDisplayName = nil
        isSignedIn = false
    }

    private func adopt(_ credentials: Credentials, client existing: SubsonicClient? = nil) {
        guard let built = existing ?? (try? SubsonicClient(credentials: credentials)) else { return }
        client = built
        serverDisplayName = URL(string: credentials.server)?.host ?? credentials.server
        isSignedIn = true
    }

    static func normalizeServer(_ raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else {
            throw SubsonicError.invalidInput(String(localized: "Enter a server URL."))
        }
        if !trimmed.contains("://") {
            let lower = trimmed.lowercased()
            let isLocal = lower.hasPrefix("localhost")
                || lower.hasPrefix("127.")
                || lower.hasPrefix("10.")
                || lower.hasPrefix("192.168.")
                || lower.contains(".local")
            trimmed = (isLocal ? "http://" : "https://") + trimmed
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw SubsonicError.invalidInput(String(localized: "Enter a valid http:// or https:// server URL."))
        }
        return url
    }

    private static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Keychain

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> Credentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    private func writeKeychain(_ credentials: Credentials) {
        deleteKeychain()
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("cannot save subsonic credentials: keychain status \(status, privacy: .public)")
        }
    }

    private func deleteKeychain() {
        SecItemDelete(query as CFDictionary)
    }
}
