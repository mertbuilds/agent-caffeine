import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRelocator.offerToMoveIfNeeded()
    }
}

@main
struct CaffeinagentApp: App {
    @StateObject private var aggregator = StateAggregator()
    @StateObject private var updater = Updater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(aggregator: aggregator)
        } label: {
            MenuBarLabel(held: aggregator.assertionHeld)
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
