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
    /// The lab commands run without the app. A plain launch is the app, and
    /// anything else is refused, so no command line starts a second copy.
    @MainActor
    static func main() {
        switch LaunchArguments.kind(of: CommandLine.arguments) {
        case .lab:
            if LabCommand.run(CommandLine.arguments) { return }
            exit(1)
        case .refused(let argument):
            FileHandle.standardError.write(Data("Unknown argument \(argument). The app starts without arguments.\n".utf8))
            exit(1)
        case .app:
            CaffeinagentApp.main()
        }
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
