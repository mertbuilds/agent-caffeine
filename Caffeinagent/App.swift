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
    /// The lab commands run without the app. A plain launch is the app
    /// when no other copy runs, and anything else is refused, so no
    /// command line starts a second copy.
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
            guard SingleInstance.mayStart(others: otherCopies, sleep: { Thread.sleep(forTimeInterval: $0) }) else {
                FileHandle.standardError.write(Data("agent caffeine is already running.\n".utf8))
                exit(0)
            }
            CaffeinagentApp.main()
        }
    }

    /// The other running copies of the app, from any folder.
    private static func otherCopies() -> Int {
        guard let bundleID = Bundle.main.bundleIdentifier else { return 0 }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != own && !$0.isTerminated }.count
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
            MenuBarLabel(look: MenuBarLook(pose: MenuModel.pose(aggregator.panelInput)))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(aggregator: aggregator, updater: updater)
        }
    }
}

/// The robot in the menu bar. It takes the pose of the robot in the menu.
struct MenuBarLabel: View {
    let look: MenuBarLook

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: look))
            .accessibilityLabel(look.accessibilityLabel)
    }
}
