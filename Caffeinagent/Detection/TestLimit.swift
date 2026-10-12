import Foundation

/// The gate of the hidden defaults that make a limit short for the test
/// runner: `ClosedLidLimit.testSecondsKey` and `OfflineRule.testSecondsKey`.
///
/// Such a default counts only while the switch of the tests is on
/// (`HoldStore.stateSwitchKey`), and it can only make a limit shorter: a
/// value that is left over, or a large one, takes no limit away.
enum TestLimit {
    /// The hidden default in seconds, 0 while the switch of the tests is off.
    static func seconds(forKey key: String, in defaults: UserDefaults) -> TimeInterval {
        defaults.bool(forKey: HoldStore.stateSwitchKey) ? defaults.double(forKey: key) : 0
    }

    /// The limit in use. `testSeconds` counts when it is above zero, and
    /// never makes the limit longer than the settings have it.
    static func shortened(_ limit: TimeInterval?, to testSeconds: TimeInterval) -> TimeInterval? {
        testSeconds > 0 ? min(testSeconds, limit ?? testSeconds) : limit
    }
}
