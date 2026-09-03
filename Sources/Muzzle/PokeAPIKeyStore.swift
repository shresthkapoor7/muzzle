import Foundation
import Security

@MainActor
final class PokeAPIKeyStore: ObservableObject {
    private static let service = "local.muzzle.app"
    private static let account = "poke-api-key"

    @Published private(set) var isConfigured: Bool

    init() {
        isConfigured = Self.loadKey() != nil
    }

    func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PokeAPIKeyStoreError.emptyKey }

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

        isConfigured = true
    }

    func remove() throws {
        let status = SecItemDelete(Self.query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PokeAPIKeyStoreError.keychain(status)
        }
        isConfigured = false
    }

    func apiKey() -> String? {
        Self.loadKey()
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
