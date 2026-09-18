import Foundation
import Security

@MainActor
final class PokeAPIKeyStore: ObservableObject {
    private static let service = "local.muzzle.app"
    private static let account = "poke-api-key"

    @Published private(set) var isConfigured: Bool
    private var cachedKey: String?
    private let readKey: () -> String?
    private let writeKey: (String) throws -> Void
    private let deleteKey: () throws -> Void

    convenience init() {
        self.init(readKey: Self.loadKey, writeKey: Self.saveKey, deleteKey: Self.removeKey)
    }

    init(readKey: @escaping () -> String?, writeKey: @escaping (String) throws -> Void,
         deleteKey: @escaping () throws -> Void) {
        self.readKey = readKey
        self.writeKey = writeKey
        self.deleteKey = deleteKey
        cachedKey = readKey()
        isConfigured = cachedKey != nil
    }

    func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PokeAPIKeyStoreError.emptyKey }
        try writeKey(key)
        cachedKey = key
        isConfigured = true
    }

    private static func saveKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query = Self.query
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw PokeAPIKeyStoreError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw PokeAPIKeyStoreError.keychain(updateStatus)
        }
    }

    func remove() throws {
        try deleteKey()
        cachedKey = nil
        isConfigured = false
    }

    private static func removeKey() throws {
        let status = SecItemDelete(Self.query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PokeAPIKeyStoreError.keychain(status)
        }
    }

    func apiKey() -> String? {
        if let cachedKey { return cachedKey }
        // A denied or unavailable read can be retried on the next delivery attempt.
        cachedKey = readKey()
        isConfigured = cachedKey != nil
        return cachedKey
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func loadKey() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}

private enum PokeAPIKeyStoreError: LocalizedError {
    case emptyKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "Enter a Poke API key."
        case let .keychain(status):
            "Muzzle could not save the Poke API key in your Keychain (status \(status))."
        }
    }
}
