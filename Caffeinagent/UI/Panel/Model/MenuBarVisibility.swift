import Foundation

/// Whether the robot is in the menu bar. The app runs the same without it.
enum MenuBarVisibility {
    static let key = "MenuBar.showIcon"

    /// Shown unless the user hid it: a value that is missing or is no
    /// boolean counts as shown, so an update never starts hidden.
    static func isShown(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    static func set(_ shown: Bool, in defaults: UserDefaults) {
        defaults.set(shown, forKey: key)
    }
}
