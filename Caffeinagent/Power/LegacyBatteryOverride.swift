import Foundation

// The builds before the helper set SleepDisabled through `sudo pmset` and
// remembered it in UserDefaults, because the flag survives a quit.
enum LegacyBatteryOverride {
    static let flagKey = "BatteryOverride.overrideSetByApp"

    /// Clears a flag such a build left on, then forgets it. It is forgotten
    /// only when the command ended well, or when the sudoers entry is gone
    /// and the command can never run. Otherwise the next launch tries again.
    /// - Parameters:
    ///   - entryExists: the sudoers entry of the old builds is there.
    ///   - clear: runs the command. Its exit code, nil when it did not run.
    static func clearLeftover(defaults: UserDefaults, entryExists: () -> Bool, clear: () -> Int32?) {
        guard defaults.bool(forKey: flagKey) else { return }
        guard entryExists() else { return defaults.removeObject(forKey: flagKey) }
        if clear() == 0 { defaults.removeObject(forKey: flagKey) }
    }
}
