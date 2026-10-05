import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRelocator.offerToMoveIfNeeded()
        // The onboarding window opens here while `Onboarding.isPending`.
    }
}

/// The seam for the onboarding window, which is not built yet. It is the
/// place to set up the lid-closed helper and to ask for notifications, and
/// it sets `completedKey` when the user is done.
enum Onboarding {
    static let completedKey = "Onboarding.completed"

    static var isPending: Bool { !UserDefaults.standard.bool(forKey: completedKey) }
}

@main
enum Main {
    /// The lab commands run without the app. Every other launch is the app.
    @MainActor
    static func main() {
        if LabCommand.run(CommandLine.arguments) { return }
        CaffeinagentApp.main()
    }
}

struct CaffeinagentApp: App {
    @StateObject private var aggregator = StateAggregator()
    @StateObject private var updater = Updater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(aggregator: aggregator)
        } label: {
            MenuBarLabel(held: aggregator.decision.hold)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(aggregator: aggregator, updater: updater)
        }
    }
}

struct MenuBarLabel: View {
    let held: Bool

    var body: some View {
        Image(nsImage: held ? MenuBarIcon.held : MenuBarIcon.notHeld)
            .accessibilityLabel(MenuBarIcon.accessibilityLabel(held: held))
    }
}
