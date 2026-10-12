import Foundation

/// What the paid versions up to 1.0.3 left on the Mac: the license record
/// in the login Keychain, and the times of the trial and of the last
/// license check in the settings. The free version needs none of them and
/// deletes them once, at its first launch.
///
/// This clean-up can be removed in a later release.
enum PaidLeftovers {
    static let settingsKeys = ["License.trialStart", "License.latestSeen", "License.lastValidated", "TrialNotice.told"]
    // A Debug build of a paid version kept an item of its own. The two
    // builds share the settings, so each remembers its clean-up under a
    // key of its own: a Debug build that starts first does not make the
    // Release build skip the real item.
    #if DEBUG
    static let removedKey = "PaidLeftovers.removed.debug"
    static let keychainService = "com.caffeinagent.app.license.debug"
    #else
    static let removedKey = "PaidLeftovers.removed"
    static let keychainService = "com.caffeinagent.app.license"
    #endif
    static let keychainAccount = "license"

    /// It is remembered only when the Keychain item is gone. Otherwise the
    /// next launch tries again.
    /// - Parameter deleteKeychainItem: false when the item is still there.
    static func remove(defaults: UserDefaults, deleteKeychainItem: () -> Bool) {
        guard !defaults.bool(forKey: removedKey) else { return }
        settingsKeys.forEach(defaults.removeObject(forKey:))
        if deleteKeychainItem() { defaults.set(true, forKey: removedKey) }
    }
}
