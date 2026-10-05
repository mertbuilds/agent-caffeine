import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRelocator.offerToMoveIfNeeded()
        // After the first sample, so the window can name the agents it found.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if Onboarding.isPending { OnboardingWindow.show(aggregator: .shared) }
        }
    }
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
    @ObservedObject private var aggregator = StateAggregator.shared
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
