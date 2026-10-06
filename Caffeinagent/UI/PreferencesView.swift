import SwiftUI

enum PreferencesTab: Hashable {
    case general
    case alerts
    case shortcuts
    case agents
    case lidClosed
    case license
    case about
}

struct PreferencesView: View {
    @ObservedObject var aggregator: StateAggregator
    @ObservedObject var updater: Updater
    @State private var licenseKey: String = ""
    @State private var confirmingDeactivate = false

    private var license: LicenseManager { aggregator.license }

    var body: some View {
        TabView(selection: $aggregator.preferencesTab) {
            GeneralPreferences(mode: $aggregator.mode, settings: $aggregator.settings, showMenuBarIcon: $aggregator.showMenuBarIcon)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)
            AlertPreferences(
                notices: $aggregator.notices, denied: aggregator.notificationPermission == .denied,
                openSystemSettings: aggregator.openNotificationSettings
            )
            .tabItem { Label("Alerts", systemImage: "bell") }
            .tag(PreferencesTab.alerts)
            ShortcutPreferences(
                shortcuts: aggregator.shortcuts, shortcutProblems: aggregator.shortcutProblems,
                setShortcut: aggregator.setShortcut, setShortcutRecording: aggregator.setShortcutRecording
            )
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            .tag(PreferencesTab.shortcuts)
            AgentPreferences(
                settings: $aggregator.settings,
                foundIDs: Set(aggregator.decision.perAgent.map(\.reading.agentID)),
                hookRows: HookRowModel.rows(statuses: aggregator.hookStatuses, errors: aggregator.hookErrors),
                hooksAvailable: aggregator.hooksAvailable,
                setHooks: aggregator.setHooks
            )
            .tabItem { Label("Agents", systemImage: "terminal") }
            .tag(PreferencesTab.agents)
            LidClosedPreferences(
                settings: $aggregator.settings,
                helper: aggregator.sleepFlag.helperStatus,
                setup: aggregator.sleepFlag.setup,
                repairTried: aggregator.sleepFlag.repairTried,
                canSetUp: aggregator.canSetUpHelper,
                needsSudoersCleanup: aggregator.sleepFlag.needsSudoersCleanup,
                error: aggregator.helperError,
                setUp: aggregator.setUpHelper,
                remove: aggregator.removeHelper,
                tryAgain: aggregator.repairHelper,
                openLoginItems: aggregator.sleepFlag.openLoginItemsSettings,
                removeSudoersEntry: aggregator.removeSudoersEntry
            )
            .tabItem { Label("Lid closed", systemImage: "laptopcomputer") }
            .tag(PreferencesTab.lidClosed)
            Form { licenseSection }
                .formStyle(.grouped)
                .tabItem { Label("License", systemImage: "key") }
                .tag(PreferencesTab.license)
            Form { aboutSection }
                .formStyle(.grouped)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(PreferencesTab.about)
        }
        .frame(width: 480, height: 500)
        .tint(.brand)
        .onAppear {
            aggregator.refreshHelperStatus()
            aggregator.refreshHookStatuses()
            aggregator.refreshNotificationPermission()
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text(AppVersion.current)
                Spacer()
                Button("Check for updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            Text("While it keeps the Mac awake, agent caffeine holds a PreventUserIdleSystemSleep assertion, plus PreventSystemSleep, so the Mac stays awake on battery and when plugged in. The display may still sleep. For a closed lid on battery, its helper also turns on the SleepDisabled setting of macOS, and turns it off when agent caffeine stops or quits.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("agent caffeine checks caffeinagent.com for updates. It checks your license key with Polar. It sends the key and your Mac's model, and nothing about you or your agents.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("a")
                    .foregroundStyle(.secondary)
                Link("mertbuilds.com", destination: Self.builderURL)
                Text("utility")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Button("Show setup again") { OnboardingWindow.show(aggregator: aggregator) }
        }
    }

    private var licenseSection: some View {
        Section("License") {
            if aggregator.entitlement == .licensed {
                Label("Licensed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                if let key = license.record.key {
                    Text("Key ending in \(String(key.suffix(6)))")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let lastValidated = license.record.lastValidated {
                    Text("Last checked \(lastValidated.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Deactivate this Mac") { confirmingDeactivate = true }
                        .disabled(license.busy)
                    if license.busy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Manage in Polar") { NSWorkspace.shared.open(license.config.customerPortalURL) }
                }
                .confirmationDialog(
                    "Deactivate agent caffeine on this Mac?",
                    isPresented: $confirmingDeactivate
                ) {
                    Button("Deactivate", role: .destructive) {
                        Task { await license.deactivate() }
                    }
                } message: {
                    Text("You can then use the key on another Mac. agent caffeine stops keeping this Mac awake until you activate a key again.")
                }
            } else if aggregator.entitlement == .expired(.unverified) {
                Text(ExpiredReason.unverified.text)
                    .foregroundStyle(.orange)
                HStack {
                    Button("Check now") { Task { await license.checkNow() } }
                        .disabled(license.busy)
                    if license.busy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Manage in Polar") { NSWorkspace.shared.open(license.config.customerPortalURL) }
                }
            } else {
                Text(licenseStatus)
                    .foregroundStyle(aggregator.entitlement.allowsHolding ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                TextField("License key", text: $licenseKey, prompt: Text("AGENTCAF-…"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(activate)
                HStack {
                    Button("Activate", action: activate)
                        .disabled(LicenseClient.cleaned(licenseKey).isEmpty || license.busy)
                    if license.busy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    // Whoever has a key already bought one.
                    if license.record.key == nil {
                        Button("Buy a key") { NSWorkspace.shared.open(license.config.checkoutURL) }
                    }
                }
            }
            if let message = license.message {
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.red)
                if message == .limitReached {
                    Link("Manage in Polar", destination: license.config.customerPortalURL)
                        .font(.callout)
                }
            }
            if let error = license.storageError {
                Text("\(error.hasSuffix(".") ? error : error + ".") agent caffeine keeps your trial and your last license check in its preferences until it can read the Keychain again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if licenseKey.isEmpty, let key = license.record.key { licenseKey = key }
        }
    }

    private var licenseStatus: String {
        switch aggregator.entitlement {
        case .trial(let daysLeft):
            return "Your trial has \(HumaneDuration.counted(daysLeft, "day")) left"
        case .expired(let reason):
            return reason.text
        case .licensed:
            return ExpiredReason.trialOver.text
        }
    }

    private func activate() {
        let key = licenseKey
        guard !LicenseClient.cleaned(key).isEmpty, !license.busy else { return }
        Task { await license.activate(key: key) }
    }

    private static let builderURL = URL(
        string: "https://mertbuilds.com/?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=about"
    )!
}

struct GeneralPreferences: View {
    @Binding var mode: AwakeMode
    @Binding var settings: DetectionSettings
    @Binding var showMenuBarIcon: Bool

    /// From 30 seconds to 30 minutes.
    private static let durations: [TimeInterval] = [30, 60, 120, 180, 300, 600, 900, 1200, 1800]

    var body: some View {
        Form {
            Section("Keep your Mac awake") {
                Picker("Keep your Mac awake", selection: $mode) {
                    ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AwakeMode.allCases) { Text($0.explanation) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if !RemoteAccessDetector.detectedTools.isEmpty {
                Section {
                    Toggle("Stay awake for phone access while plugged in", isOn: $settings.stayAwakeForRemoteAccess)
                    Text("This is for Claude Code Remote Control. While your Mac is plugged in and Remote Control is on, your Mac stays awake, even when no agent is working. On battery, choose \"Stay reachable\" in the menu to keep your Mac awake for a set time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("How long your Mac stays awake") {
                duration(
                    "After an agent finishes", $settings.releaseAfterState,
                    help: "Claude Code and Codex say when they finish. Your Mac stays awake this long afterwards, so it does not sleep in a short break between two tasks."
                )
                duration(
                    "After other agents go quiet", $settings.releaseAfterActivity,
                    help: "Other agents do not say when they finish. For those, agent caffeine watches for activity, such as a running command, and your Mac stays awake this long after the last of it."
                )
                duration(
                    "While an agent is waiting for you", $settings.waitingHold,
                    help: "Your Mac stays awake this long while an agent is waiting for your answer. After that it can sleep."
                )
            }
            Section {
                Toggle("Show agent caffeine in the menu bar", isOn: $showMenuBarIcon)
                Text("When hidden, open agent caffeine again from Applications or Spotlight to see this window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func duration(_ title: String, _ value: Binding<TimeInterval>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: value) {
                // A value that is not on the list stays selectable.
                ForEach(Set(Self.durations + [value.wrappedValue]).sorted(), id: \.self) {
                    Text(Self.text(for: $0)).tag($0)
                }
            }
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private static func text(for seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        if seconds < 60 || seconds % 60 != 0 { return "\(seconds) seconds" }
        return seconds == 60 ? "1 minute" : "\(seconds / 60) minutes"
    }
}

/// The notifications about agents. The ones about a safety stop have no
/// switch: nobody should miss why the Mac slept.
struct AlertPreferences: View {
    @Binding var notices: AgentNoticeSettings
    /// Notifications are switched off for agent caffeine in System Settings.
    var denied = false
    var openSystemSettings: () -> Void = {}

    var body: some View {
        Form {
            if denied {
                Section {
                    HStack {
                        Label("Notifications are off for agent caffeine in System Settings", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings", action: openSystemSettings)
                    }
                }
            }
            Section("Notify me when") {
                toggle(
                    "An agent is waiting for your answer", $notices.waiting,
                    help: "You get a notification when an agent asks you a question or needs your permission."
                )
                toggle(
                    "An agent finished", $notices.finished,
                    help: "You get a notification when an agent finishes work that took 30 seconds or longer."
                )
            }
            Section {
                toggle(
                    "Only notify when the agent's window is not in front", $notices.onlyWhenAway,
                    help: "You get no notification while you use the app the agent runs in."
                )
                .disabled(!notices.wantsAny)
            }
            Section {
                Text("agent caffeine always tells you when it lets your Mac sleep because the battery is low or your Mac got too hot. These notifications have no switch, so you do not miss them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ title: String, _ value: Binding<Bool>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: value)
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShortcutPreferences: View {
    var shortcuts: [ShortcutAction: Shortcut] = [:]
    var shortcutProblems: [ShortcutAction: ShortcutProblem] = [:]
    var setShortcut: (Shortcut?, ShortcutAction) -> Void = { _, _ in }
    var setShortcutRecording: (Bool) -> Void = { _ in }

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRecorder(
                        title: action.title, shortcut: shortcuts[action], problem: shortcutProblems[action],
                        set: { setShortcut($0, action) }, setRecording: setShortcutRecording
                    )
                }
                Text("The shortcuts work in every app. Click a field, then press the keys you want.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AgentPreferences: View {
    @Binding var settings: DetectionSettings
    /// `AgentDefinition.id` of the agents that run now.
    let foundIDs: Set<String>
    var hookRows: [HookRowModel] = []
    var hooksAvailable = true
    var setHooks: (HookCatalogEntry, Bool) -> Void = { _, _ in }
    @State private var newName = ""

    /// A definition without matchers is a placeholder that finds nothing.
    private static let definitions = AgentCatalog.standard.definitions.filter { !$0.matchers.isEmpty }

    var body: some View {
        Form {
            Section("Open on this Mac now") {
                let found = Self.definitions.filter { foundIDs.contains($0.id) }
                if found.isEmpty {
                    Text("No agent is open")
                        .foregroundStyle(.secondary)
                }
                ForEach(found, id: \.id, content: row)
            }
            if !hookRows.isEmpty {
                HookPreferencesSection(rows: hookRows, available: hooksAvailable, set: setHooks)
            }
            Section("Other agents") {
                ForEach(Self.definitions.filter { !foundIDs.contains($0.id) }, id: \.id, content: row)
            }
            Section("Other tools") {
                Text("Add the process name of a tool that is not in the list. It counts as working while it is using the processor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(settings.userAgentNames, id: \.self) { name in
                    HStack {
                        Text(name).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { remove(name) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(name)")
                    }
                }
                HStack {
                    TextField("Process name", text: $newName, prompt: Text("Process name, for example mytool"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ definition: AgentDefinition) -> some View {
        Picker(selection: rule(for: definition.id)) {
            ForEach(AgentRule.allCases, id: \.self) { Text($0.title).tag($0) }
        } label: {
            Text(definition.kind == .desktop ? "\(definition.displayName) app" : definition.displayName)
            if !definition.verified {
                Text("Not tested yet")
            }
        }
    }

    /// An agent with no entry is automatic, so that choice removes the entry.
    private func rule(for id: String) -> Binding<AgentRule> {
        Binding(
            get: { settings.rule(for: id) },
            set: { settings.agentRules[id] = $0 == .automatic ? nil : $0 }
        )
    }

    private func add() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.userAgentNames.contains(trimmed) else { return }
        settings.userAgentNames.append(trimmed)
        newName = ""
    }

    private func remove(_ name: String) {
        settings.userAgentNames.removeAll { $0 == name }
    }
}

extension AgentRule {
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .alwaysWorkingWhileOpen: return "Always counts as working"
        case .ignore: return "Ignore"
        }
    }
}

struct LidClosedPreferences: View {
    @Binding var settings: DetectionSettings
    let helper: HelperStatus
    let setup: HelperSetup
    /// The helper was registered again and still gives no answer.
    var repairTried = false
    /// The helper is offered only from the Applications folder.
    let canSetUp: Bool
    let needsSudoersCleanup: Bool
    let error: String?
    let setUp: () -> Void
    let remove: () -> Void
    var tryAgain: () -> Void = {}
    let openLoginItems: () -> Void
    let removeSudoersEntry: () -> Void

    var body: some View {
        Form {
            Section("Lid closed") {
                Text("On battery, macOS puts your Mac to sleep when you close the lid, even while an agent is working. agent caffeine can prevent that with a small helper that you allow once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                helperState
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Stay awake with the lid closed on battery", isOn: $settings.stayAwakeLidClosedOnBattery)
                    .disabled(helper != .enabled)
                Stepper(value: $settings.batteryFloorPercent, in: 5...50, step: 5) {
                    Text("Let your Mac sleep below \(settings.batteryFloorPercent) percent battery")
                }
                Text("agent caffeine also lets your Mac sleep when it gets too hot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Turn the display off when the lid is closed", isOn: $settings.displayOffLidClosed)
                Text("With the lid closed, agent caffeine keeps the built-in display dark so it does not use the battery or warm your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if needsSudoersCleanup {
                Section {
                    Text("An older version of agent caffeine added an admin entry to this Mac. It is no longer used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Remove the old admin entry", action: removeSudoersEntry)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var helperState: some View {
        switch setup {
        case .repairing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(PanelText.helperRepairing)
            }
        case .notResponding:
            Label(PanelText.helperNotResponding, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            HStack {
                Button(PanelText.title(of: .tryHelperAgain), action: tryAgain)
                if repairTried {
                    Button(PanelText.title(of: .openLoginItems), action: openLoginItems)
                }
            }
        case .ready:
            HStack {
                Label("The helper is set up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Remove", action: remove)
            }
        case .requiresApproval:
            HStack {
                Text("Allow agent caffeine in System Settings > General > Login Items")
                Spacer()
                Button("Open System Settings", action: openLoginItems)
            }
        case .lost:
            if canSetUp {
                HStack {
                    Text(PanelText.helperLost)
                    Spacer()
                    Button("Set up…", action: setUp)
                }
            } else {
                Text("Move agent caffeine to the Applications folder to set this up")
            }
        case .notSetUp:
            if canSetUp {
                Button("Set up…", action: setUp)
            } else {
                Text("Move agent caffeine to the Applications folder to set this up")
            }
        }
    }
}

#if DEBUG
private struct PreferencesPreview: View {
    var helper = HelperStatus.notRegistered
    var setup = HelperSetup.notSetUp
    var needsSudoersCleanup = false
    @State private var mode = AwakeMode.agentWorking
    @State private var settings = DetectionSettings()
    @State private var showMenuBarIcon = true
    @State private var notices = AgentNoticeSettings()

    var body: some View {
        TabView {
            GeneralPreferences(mode: $mode, settings: $settings, showMenuBarIcon: $showMenuBarIcon)
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertPreferences(notices: $notices, denied: true)
                .tabItem { Label("Alerts", systemImage: "bell") }
            ShortcutPreferences()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AgentPreferences(
                settings: $settings, foundIDs: ["claude", "codex-desktop"],
                hookRows: HookRowModel.rows(statuses: ["claude": .installed(version: 1), "codex": .outdated, "droid": .notInstalled])
            )
                .tabItem { Label("Agents", systemImage: "terminal") }
            LidClosedPreferences(
                settings: $settings, helper: helper, setup: setup, repairTried: true, canSetUp: true, needsSudoersCleanup: needsSudoersCleanup, error: nil,
                setUp: {}, remove: {}, openLoginItems: {}, removeSudoersEntry: {}
            )
            .tabItem { Label("Lid closed", systemImage: "laptopcomputer") }
        }
        .frame(width: 480, height: 500)
        .tint(.brand)
    }
}

#Preview("Preferences") {
    PreferencesPreview()
}

#Preview("Helper set up, old entry left") {
    PreferencesPreview(helper: .enabled, setup: .ready, needsSudoersCleanup: true)
}

#Preview("Helper gives no answer") {
    PreferencesPreview(helper: .enabled, setup: .notResponding)
}

#Preview("Helper waits for approval") {
    PreferencesPreview(helper: .requiresApproval, setup: .requiresApproval)
}

#Preview("Helper is set up again") {
    PreferencesPreview(setup: .repairing)
}

#Preview("Helper lost") {
    PreferencesPreview(setup: .lost)
}
#endif
