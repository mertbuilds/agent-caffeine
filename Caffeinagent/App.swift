import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var reopenObserver: NSObjectProtocol?
    private var toolTipObserver: AnyCancellable?
    private var reopenGate = ReopenGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No offer to move, no setup window and no word from other copies.
        guard !SmokeTest.isActive else { return SmokeTest.appDidLaunch() }
        AppRelocator.offerToMoveIfNeeded()
        // After the change, and not more often than the icon can change.
        toolTipObserver = StateAggregator.shared.objectWillChange
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { _ in MainActor.assumeIsolated { MenuBarToolTip.update(.shared) } }
        // After the first sample, so the window can name the agents it found.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if Onboarding.isPending { OnboardingWindow.show(aggregator: .shared) }
        }
        Notifier.shared.onResponse = { [weak self] time in self?.reopenGate.notificationClicked(at: time) }
        // A second copy that leaves asks for Preferences this way. What it
        // sends is not read. No click of a notification sends it, so
        // Preferences opens at once.
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Reopen.notificationName), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPreferences() }
        }
    }

    /// The user opened the app again, from the Finder or Spotlight, or
    /// clicked a notification: see `ReopenGate`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard let reopen = reopenGate.reopened(at: ProcessInfo.processInfo.systemUptime) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + ReopenGate.wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.reopenGate.waitEnded(reopen) else { return }
                self.showPreferences()
            }
        }
        return false
    }

    /// Also with the icon shown: macOS hides it when the menu bar is full.
    @MainActor
    private func showPreferences() {
        StateAggregator.shared.preferencesTab = .general
        PreferencesWindow.show()
    }
}

@main
enum Main {
    /// The lab commands run without the app, and the smoke test runs the
    /// app with nothing behind it. A plain launch is the app when no
    /// other copy runs, and anything else is refused, so no
    /// command line starts a second copy. A second copy asks the first
    /// for Preferences and leaves.
    @MainActor
    static func main() {
        let kind = LaunchArguments.kind(of: CommandLine.arguments)
        let anotherCopyRuns = kind == .app
            && !SingleInstance.mayStart(others: { otherCopies().count }, sleep: { Thread.sleep(forTimeInterval: $0) })
        switch Reopen.action(kind: kind, anotherCopyRuns: anotherCopyRuns) {
        case .runLab:
            if LabCommand.run(CommandLine.arguments) { return }
            exit(1)
        case .runSmokeTest(let seconds):
            SmokeTest.prepare(seconds: seconds)
            CaffeinagentApp.main()
        case .runDisplayProbe(let seconds):
            DisplayProbe.run(seconds: seconds)
        case .refuse(let argument):
            FileHandle.standardError.write(Data("Unknown argument \(argument). The app starts without arguments.\n".utf8))
            exit(1)
        case .askRunningCopy:
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Reopen.notificationName), object: nil, userInfo: nil, deliverImmediately: true
            )
            _ = otherCopies().first?.activate(options: [])
            FileHandle.standardError.write(Data("Agent Caffeine is already running.\n".utf8))
            exit(0)
        case .start:
            CaffeinagentApp.main()
        }
    }

    /// The other running copies of the app, from any folder.
    private static func otherCopies() -> [NSRunningApplication] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != own && !$0.isTerminated }
    }
}

struct CaffeinagentApp: App {
    @ObservedObject private var aggregator = StateAggregator.shared
    @StateObject private var updater = Updater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// `MenuBarExtra` must not get `$aggregator.showMenuBarIcon`. On macOS 26
    /// every update of the scenes sets the status item's visibility again,
    /// also to the value it has, and SwiftUI's observer of it writes that
    /// value back through this binding. A binding that publishes on such a
    /// write updates the scenes again, for ever, on the main thread: the
    /// app uses a whole core and its icon is blank and dead. `@AppStorage`
    /// publishes on every write too and hangs the same way, so it is no
    /// fix. Here a write of the same value goes nowhere.
    static func menuBarIconInserted(_ aggregator: StateAggregator) -> Binding<Bool> {
        Binding(
            get: { aggregator.showMenuBarIcon },
            set: { if $0 != aggregator.showMenuBarIcon { aggregator.showMenuBarIcon = $0 } }
        )
    }

    var body: some Scene {
        let _ = SmokeTest.countSceneEvaluation()
        MenuBarExtra(isInserted: Self.menuBarIconInserted(aggregator)) {
            MenuBarView(aggregator: aggregator)
        } label: {
            let input = aggregator.panelInput
            MenuBarLabel(look: MenuBarLook(pose: MenuModel.pose(input)), spoken: MenuModel.menuBarAccessibilityLabel(input))
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
    /// In place of what the look says, when the state says more.
    var spoken: String?

    var body: some View {
        Image(nsImage: MenuBarIcon.image(for: look))
            .accessibilityLabel(spoken ?? look.accessibilityLabel)
    }
}
