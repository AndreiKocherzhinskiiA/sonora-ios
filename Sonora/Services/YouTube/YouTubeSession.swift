import Foundation
import Observation
import Security
import os

/// The signed-in YouTube Music account: its cookie header, kept in the keychain, and the client
/// built on it. Views read `isSignedIn`, and playback and search ask for `client`.
@Observable
final class YouTubeSession {
    private(set) var isSignedIn = false
    private(set) var client: YouTubeClient?

    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "youtube")
    @ObservationIgnored private let account = "youtube-cookies"
    @ObservationIgnored private let service = "org.sonorahq.sonora"

    /// Cookies that prove a browser session is signed in.
    static let proof = ["SAPISID", "__Secure-3PAPISID"]

    /// Reads a saved session, if there is one. Call once at launch.
    func restore() {
        guard let header = readKeychain() else { return }
        adopt(header)
    }

    /// Signs in with a `Cookie` header, refusing one that carries no proof of an account.
    func signIn(cookies header: String) throws {
        guard YouTubeClient.sapisid(in: header) != nil else {
            throw YouTubeError.api("The cookies carry no SAPISID or __Secure-3PAPISID.")
        }
        writeKeychain(header)
        adopt(header)
    }

    func signOut() {
        deleteKeychain()
        client = nil
        isSignedIn = false
    }

    private func adopt(_ header: String) {
        client = YouTubeClient(cookies: header)
        isSignedIn = true
    }

    // MARK: Keychain

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychain(_ header: String) {
        deleteKeychain()
        var item = query
        item[kSecValueData as String] = Data(header.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("cannot save the youtube session: keychain status \(status, privacy: .public)")
        }
    }

    private func deleteKeychain() {
        SecItemDelete(query as CFDictionary)
    }
}
