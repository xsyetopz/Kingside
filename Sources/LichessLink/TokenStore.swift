import Foundation
import Security

/// Persists the Lichess access token.
public protocol TokenStore: Sendable {
    func token() -> String?
    func save(_ token: String) throws
    func delete() throws
}

public struct KeychainError: Error, Equatable, Sendable {
    public var status: OSStatus
}

/// A generic-password keychain item that syncs through iCloud Keychain, so a sign-in on iPhone
/// reaches Apple TV.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// Matches the item whether or not it is synchronizable.
    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    public func token() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        try delete()
        var item = query
        item[kSecAttrSynchronizable as String] = kCFBooleanTrue
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// For tests.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    public init(token: String? = nil) {
        stored = token
    }

    public func token() -> String? {
        lock.withLock { stored }
    }

    public func save(_ token: String) throws {
        lock.withLock { stored = token }
    }

    public func delete() throws {
        lock.withLock { stored = nil }
    }
}
