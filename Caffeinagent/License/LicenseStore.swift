import Foundation

/// Where the license record lives between launches.
protocol LicenseStore: AnyObject {
    /// Nil when nothing was stored yet. Throws when the storage cannot be read,
    /// which is not the same as empty.
    func load() throws -> LicenseRecord?
    func save(_ record: LicenseRecord) throws
}

struct LicenseStoreError: Error, Equatable {
    let message: String
}
