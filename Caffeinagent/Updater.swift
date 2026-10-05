import AppKit
import Combine
import Sparkle

/// Sparkle's updater, created once at launch and kept for the app's lifetime.
/// The feed, the public key and the daily schedule are in Info.plist.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    // Sparkle holds its user driver delegate weakly.
    private let userDriverDelegate: DockIconUserDriverDelegate

    init() {
        // A Debug build has no feed of its own, so it never starts the updater
        // and never checks.
        #if DEBUG
        let startUpdater = false
        #else
        let startUpdater = true
        #endif
        let userDriverDelegate = DockIconUserDriverDelegate()
        self.userDriverDelegate = userDriverDelegate
        controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: nil,
            userDriverDelegate: userDriverDelegate
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// The app is usually not active when the button is clicked, and Sparkle's
    /// windows would open behind the app in front.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

/// The app has no Dock icon (LSUIElement), so an update found by a scheduled
/// check would sit in a window behind other apps that is easy to lose.
/// Following Sparkle's gentle reminders guide for background apps, the app
/// takes a Dock icon while an update is shown and gives it back when the
/// update session ends.
private final class DockIconUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.setActivationPolicy(.regular)
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
}
