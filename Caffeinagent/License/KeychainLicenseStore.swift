import Foundation
import Security

/// Keeps the license record in one generic password item in the user's login
/// Keychain, so a reinstall or deleted preferences neither restarts the trial
/// nor loses the license.
final class KeychainLicenseStore: LicenseStore {
    // A Debug build activates sandbox keys, which mean nothing to a Release
    // build on the same Mac, so the two keep separate items.
    #if DEBUG
    private static let service = "com.caffeinagent.app.license.debug"
    #else
    private static let service = "com.caffeinagent.app.license"
    #endif
    private static let account = "license"

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func load() throws -> LicenseRecord? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Self.error(status)
        }
        // Unreadable bytes hold nothing worth keeping; the next save replaces them.
        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    func save(_ record: LicenseRecord) throws {
        let data = try JSONEncoder().encode(record)
        let update = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Self.error(update) }
        var add = itemQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "agent caffeine license"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    private static func error(_ status: OSStatus) -> LicenseStoreError {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return LicenseStoreError(message: "Agent Caffeine could not use the Keychain: \(reason)")
    }
}
