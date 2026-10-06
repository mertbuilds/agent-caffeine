import AppKit
import SwiftUI

/// The pages of the setup window. It holds no logic of its own: what it
/// shows and what its buttons do come from outside.
struct OnboardingView: View {
    let steps: [OnboardingStep]
    /// Names of the agents that are open now.
    let foundAgents: [String]
    /// The agents whose hooks can be turned on.
    let hookRows: [HookRowModel]
    let batteryFloorPercent: Int
    let helper: HelperStatus
    let helperError: String?
    /// True when every agent was changed.
    let turnOnHooks: ([HookCatalogEntry]) -> Bool
    let setUpHelper: () -> Void
    let openLoginItems: () -> Void
    let finish: () -> Void
    @State var index = 0
    @State private var unchecked: Set<String> = []
    @State private var askedForHelper = false

    private var step: OnboardingStep { steps.indices.contains(index) ? steps[index] : .done }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case .welcome: welcome
            case .hooks: hooks
            case .lidClosed: lidClosed
            case .done: done
            }
        }
        .padding(28)
        .frame(width: 480, alignment: .leading)
        .tint(.brand)
    }

    private func next() {
        if index + 1 < steps.count {
            index += 1
        } else {
            finish()
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buttons<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }

    // MARK: Pages

    @ViewBuilder
    private var welcome: some View {
        title("agent caffeine keeps your Mac awake while your agents work")
        paragraph("When the last agent is done, your Mac can sleep again. agent caffeine lives in the menu bar and needs no window.")
        VStack(alignment: .leading, spacing: 6) {
            Text("Open on this Mac now")
            if foundAgents.isEmpty {
                paragraph("No agent is open right now. agent caffeine notices an agent as soon as it starts.")
            }
            ForEach(foundAgents, id: \.self) { name in
                Label(name, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        buttons {
            Button("Skip setup", action: finish)
        } trailing: {
            Button("Continue", action: next)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var hooks: some View {
        title("See exactly what your agents are doing")
        paragraph("An agent can tell agent caffeine when it is working, when it is waiting for you and when it is done. To make that work, agent caffeine adds a few lines to each agent's settings file. It saves a copy of the file first, and it never reads what you type.")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(hookRows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(row.entry.displayName, isOn: Binding(
                        get: { !unchecked.contains(row.id) },
                        set: { if $0 { unchecked.remove(row.id) } else { unchecked.insert(row.id) } }
                    ))
                    .toggleStyle(.checkbox)
                    Group {
                        Text("Changes ~/\(row.entry.configPath)")
                        if let note = row.entry.afterInstall { Text(note) }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                    if let error = row.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.leading, 20)
                    }
                }
            }
        }
        paragraph("You can turn this off in Preferences > Agents. That removes the lines again.")
        buttons {
            EmptyView()
        } trailing: {
            Button("Skip", action: next)
            Button("Turn on") {
                if turnOnHooks(hookRows.filter { !unchecked.contains($0.id) }.map(\.entry)) { next() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(hookRows.allSatisfy { unchecked.contains($0.id) })
        }
    }

    @ViewBuilder
    private var lidClosed: some View {
        title("Keep working with the lid closed")
        paragraph("On battery, macOS puts your Mac to sleep when you close the lid, even while an agent is working. agent caffeine can prevent that with a small helper that you allow once.")
        paragraph("Your Mac still sleeps below \(batteryFloorPercent) percent battery and when it gets too hot.")
        if helper == .enabled {
            Label("The helper is set up", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if helper == .requiresApproval {
            HStack {
                Text("Allow agent caffeine in System Settings > General > Login Items")
                Spacer()
                Button("Open System Settings", action: openLoginItems)
            }
        }
        if let helperError {
            Text(helperError)
                .font(.caption)
                .foregroundStyle(.red)
        }
        buttons {
            EmptyView()
        } trailing: {
            if askedForHelper || helper == .enabled {
                Button("Continue", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Skip", action: next)
                Button("Set up…") {
                    askedForHelper = true
                    setUpHelper()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var done: some View {
        title("agent caffeine is ready")
        paragraph("It lives in the menu bar. You can change everything in Preferences, and open this setup again in Preferences > About.")
        buttons {
            EmptyView()
        } trailing: {
            Button("Done", action: finish)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// Feeds the pages from the aggregator. The steps are fixed when the
/// window opens, so a page does not vanish while the user is on it.
private struct OnboardingContainer: View {
    @ObservedObject var aggregator: StateAggregator
    let steps: [OnboardingStep]
    /// The agents that were offered when the window opened.
    let offered: Set<String>
    let finish: () -> Void

    var body: some View {
        OnboardingView(
            steps: steps,
            foundAgents: Self.names(aggregator.decision.perAgent.map(\.reading.displayName)),
            hookRows: HookRowModel.rows(statuses: aggregator.hookStatuses, errors: aggregator.hookErrors).filter { offered.contains($0.id) },
            batteryFloorPercent: aggregator.settings.batteryFloorPercent,
            helper: aggregator.sleepFlag.helperStatus,
            helperError: aggregator.helperError,
            turnOnHooks: { entries in
                entries.forEach { aggregator.setHooks($0, on: true) }
                return entries.allSatisfy { aggregator.hookErrors[$0.id] == nil }
            },
            setUpHelper: aggregator.setUpHelper,
            openLoginItems: aggregator.sleepFlag.openLoginItemsSettings,
            finish: finish
        )
    }

    /// Each name once, in the order found.
    private static func names(_ all: [String]) -> [String] {
        var seen: Set<String> = []
        return all.filter { seen.insert($0).inserted }
    }
}

/// The setup window. Closing it counts as done, so it is not shown again
/// on its own. Preferences > About opens it again.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    static func show(aggregator: StateAggregator) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        aggregator.refreshHookStatuses()
        aggregator.refreshHelperStatus()
        let rows = HookRowModel.rows(statuses: aggregator.hookStatuses).filter { $0.status == .notInstalled || $0.status == .outdated }
        let steps = Onboarding.steps(
            hookStatuses: rows.map(\.status), hooksAvailable: aggregator.hooksAvailable,
            canSetUpHelper: aggregator.canSetUpHelper, hasBattery: aggregator.hasBattery,
            helperEnabled: aggregator.sleepFlag.helperStatus == .enabled
        )
        let content = OnboardingContainer(aggregator: aggregator, steps: steps, offered: Set(rows.map(\.id))) { window?.close() }
        let created = NSWindow(contentViewController: NSHostingController(rootView: content))
        created.title = "Set up agent caffeine"
        created.styleMask = [.titled, .closable]
        created.isReleasedWhenClosed = false
        created.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: created, queue: .main) { _ in
            Onboarding.markCompleted()
            MainActor.assumeIsolated {
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver = nil
                window = nil
            }
        }
        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
private struct OnboardingPreview: View {
    var index = 0
    var helper = HelperStatus.notRegistered
    var rows = HookRowModel.rows(statuses: ["claude": .notInstalled, "codex": .notInstalled, "opencode": .notInstalled])

    var body: some View {
        OnboardingView(
            steps: [.welcome, .hooks, .lidClosed, .done], foundAgents: ["Claude Code", "Codex"], hookRows: rows,
            batteryFloorPercent: 20, helper: helper, helperError: nil,
            turnOnHooks: { _ in true }, setUpHelper: {}, openLoginItems: {}, finish: {}, index: index
        )
    }
}

#Preview("Welcome") { OnboardingPreview() }
#Preview("Hooks") { OnboardingPreview(index: 1) }
#Preview("Lid closed") { OnboardingPreview(index: 2) }
#Preview("Lid closed, waits for approval") { OnboardingPreview(index: 2, helper: .requiresApproval) }
#Preview("Done") { OnboardingPreview(index: 3) }
#endif
