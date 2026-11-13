import Foundation
import Observation
import Security

/// Holds the signed-in Deezer `arl` session cookie in Keychain and keeps a `DeezerClient` ready.
@Observable
final class DeezerSession {
    private(set) var arl: String?
    private(set) var client: DeezerClient?

    var isSignedIn: Bool { client != nil }

    private let service = "org.sonorahq.sonora"
    private let account = "deezer-arl"

    func restore() {
        guard let saved = readKeychain(), let parsed = Self.parseARL(saved) else { return }
        arl = parsed
        client = DeezerClient(arl: parsed)
    }

    func signIn(arlInput: String) throws {
        guard let parsed = Self.parseARL(arlInput) else {
            throw DeezerError.invalidARL
        }
        try saveKeychain(parsed)
        arl = parsed
        client = DeezerClient(arl: parsed)
    }

    func signOut() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        arl = nil
        client = nil
    }

    /// Accepts either a raw `arl` value or a `Cookie`-style string containing `arl=...`.
    static func parseARL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let extracted: String
        if trimmed.contains("arl=") {
            let parts = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let pair = parts.first(where: { $0.hasPrefix("arl=") }) else { return nil }
            extracted = String(pair.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        } else {
            extracted = trimmed
        }
        guard extracted.count >= 32, extracted.allSatisfy(\.isHexDigit) else { return nil }
        return extracted
    }

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveKeychain(_ value: String) throws {
        let data = Data(value.utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = match.merging(attributes) { _, new in new }
            item[kSecClass as String] = kSecClassGenericPassword
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw DeezerError.keychain(added) }
        } else if updated != errSecSuccess {
            throw DeezerError.keychain(updated)
        }
    }
}

enum DeezerError: LocalizedError {
    case invalidARL
    case signedOut
    case badResponse
    case refused(String)
    case unplayable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidARL: String(localized: "Enter a valid Deezer ARL token.")
        case .signedOut: String(localized: "Sign in to Deezer in Settings to play or browse.")
        case .badResponse: String(localized: "Deezer returned an unexpected response.")
        case .refused(let message): message
        case .unplayable: String(localized: "No playable stream was offered for this Deezer track.")
        case .keychain(let status): String(localized: "Could not store Deezer session (\(status)).")
        }
    }
}
