import AppKit
import Combine
import Sparkle

/// Sparkle's updater, created once at launch and kept for the app's lifetime.
/// The feed, the public key and the daily schedule are in Info.plist.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    /// Nil in the smoke test, which runs the app without Sparkle.
    private let controller: SPUStandardUpdaterController?
    // Sparkle holds its delegates weakly.
    private let userDriverDelegate: DockIconUserDriverDelegate
    private let updaterDelegate = UpdateWindowDelegate()
    private var cancellables: Set<AnyCancellable> = []

    /// - Parameter license: its key's year of updates limits what Sparkle
    ///   offers. Nil offers every update.
    init(license: LicenseManager? = nil) {
        // A Debug build has no feed of its own, so it never starts the updater
        // and never checks.
        #if DEBUG
        let startUpdater = false
        #else
        let startUpdater = true
        #endif
        let userDriverDelegate = DockIconUserDriverDelegate()
        self.userDriverDelegate = userDriverDelegate
        guard !SmokeTest.isActive else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        if let license {
            // From the record that is sent: in the sink the property still
            // holds the one before.
            let release = license.release
            license.$record
                .sink { [updaterDelegate] record in
                    updaterDelegate.windowEnd = UpdateWindow.sparkleWindowEnd(record: record, release: release)
                }
                .store(in: &cancellables)
        }
    }

    /// The app is usually not active when the button is clicked, and Sparkle's
    /// windows would open behind the app in front.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

/// Offers only the updates released within the year of updates of the
/// key: a later build would not run with it. Sparkle calls it on the main
/// thread, where `windowEnd` is set.
private final class UpdateWindowDelegate: NSObject, SPUUpdaterDelegate {
    var windowEnd: Date?

    /// Nil leaves the choice to Sparkle. Otherwise the newest item of the
    /// window, or none when that is not newer than this build.
    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        guard let windowEnd else { return nil }
        let comparator = SUStandardVersionComparator.default
        let allowed = appcast.items.filter { UpdateWindow.offers(updateDated: $0.date, windowEnd: windowEnd) }
        let best = allowed.max { comparator.compareVersion($0.versionString, toVersion: $1.versionString) == .orderedAscending }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard let best, comparator.compareVersion(best.versionString, toVersion: current) == .orderedDescending else {
            return .empty()
        }
        return best
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
