import Foundation
import Security

/// Room credentials and hidden commitments never enter preferences or logs.
@MainActor enum SessionVault {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.enotix.twivvy.session",
        kSecAttrAccount as String: "current"
    ]
    static func read() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    @discardableResult static func save(_ data: Data) -> Bool {
        let values = [kSecValueData as String: data]
        let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
        return result == errSecSuccess
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
