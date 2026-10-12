import Foundation
import Security

extension PaidLeftovers {
    static func remove(defaults: UserDefaults = .standard) {
        remove(defaults: defaults, deleteKeychainItem: deleteKeychainItem)
    }

    /// An item that was never there counts as gone.
    private static func deleteKeychainItem() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
