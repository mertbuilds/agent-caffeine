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
            GeneralPreferences(
                mode: $aggregator.mode, settings: $aggregator.settings, showMenuBarIcon: $aggregator.showMenuBarIcon,
                loginItem: aggregator.loginItem, loginItemError: aggregator.loginItemError,
                setOpenAtLogin: aggregator.setOpenAtLogin, openLoginItems: aggregator.sleepFlag.openLoginItemsSettings
            )
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)
            AlertPreferences(
                notices: $aggregator.notices, denied: aggregator.notificationPermission == .denied,
                history: aggregator.noticeHistory.entries,
                batteryFloorEnabled: aggregator.settings.batteryFloorEnabled,
                openSystemSettings: aggregator.openNotificationSettings
            )
            .tabItem { Label("Notifications", systemImage: "bell") }
            .tag(PreferencesTab.alerts)
            ShortcutPreferences(
                choices: aggregator.shortcutChoices, shortcutProblems: aggregator.shortcutProblems,
                setShortcut: aggregator.setShortcut, resetShortcut: aggregator.resetShortcut, setShortcutRecording: aggregator.setShortcutRecording
            )
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            .tag(PreferencesTab.shortcuts)
            AgentPreferences(
                settings: $aggregator.settings,
                foundIDs: Set(aggregator.decision.perAgent.map(\.reading.agentID)),
                hookRows: HookRowModel.rows(statuses: aggregator.hookStatuses, errors: aggregator.hookErrors),
                hooksAvailable: aggregator.hooksAvailable,
                setHooks: aggregator.setHooks,
                showsOtherTools: $aggregator.showsOtherTools,
                agentSetup: aggregator.agentSetup,
                setUpForAgents: { aggregator.setUpForAgents() },
                installSkill: aggregator.installSkill,
                linkTool: aggregator.linkTool,
                removeAgentSetup: aggregator.removeAgentSetup
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
                hasLidAngleSensor: aggregator.hasLidAngleSensor,
                error: aggregator.helperError,
                setUp: aggregator.setUpHelper,
                remove: aggregator.removeHelper,
                tryAgain: aggregator.repairHelper,
                openLoginItems: aggregator.sleepFlag.openLoginItemsSettings,
                removeSudoersEntry: aggregator.removeSudoersEntry,
                playChime: aggregator.playLidChime
            )
            .tabItem { Label("Battery and lid", systemImage: "laptopcomputer") }
            .tag(PreferencesTab.lidClosed)
            Form { licenseSection }
                .formStyle(.grouped)
                .tabItem { Label("License", systemImage: "key") }
                .tag(PreferencesTab.license)
            AboutPreferences(
                version: AppVersion.current,
                canCheckForUpdates: updater.canCheckForUpdates,
                hooksOn: HookRowModel.rows(statuses: aggregator.hookStatuses).filter(\.isOn).map(\.entry),
                helperRegistered: aggregator.sleepFlag.helperStatus != .notRegistered,
                agentSetupOn: aggregator.agentSetup.isSetUp,
                licensed: aggregator.entitlement == .licensed && license.record.activationID != nil,
                busy: license.busy,
                checkForUpdates: updater.checkForUpdates,
                showSetup: { OnboardingWindow.show(aggregator: aggregator) },
                turnOffHooks: { $0.forEach { aggregator.setHooks($0, on: false) } },
                removeHelper: aggregator.removeHelper,
                removeAgentSetup: aggregator.removeAgentSetup,
                deactivate: { confirmingDeactivate = true },
                showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) },
                quit: { NSApp.terminate(nil) }
            )
            .tabItem { Label("About", systemImage: "info.circle") }
            .tag(PreferencesTab.about)
        }
        .frame(width: 480, height: 500)
        .tint(.brand)
        // On the window: the tabs License and About both ask it.
        .confirmationDialog(Self.deactivateQuestion, isPresented: $confirmingDeactivate) {
            Button("Deactivate", role: .destructive) {
                Task { await license.deactivate() }
            }
        } message: {
            Text(Self.deactivateConsequence)
        }
        .onAppear {
            aggregator.refreshHelperStatus()
            aggregator.refreshHookStatuses()
            aggregator.refreshAgentSetup()
            aggregator.refreshNotificationPermission()
            aggregator.refreshLoginItem()
        }
    }

    private static let deactivateQuestion = "Deactivate Agent Caffeine on this Mac?"
    private static let deactivateConsequence = "You can then use the key on another Mac. Agent Caffeine stops keeping this Mac awake until you activate a key again."

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
                if let macs = license.record.macLimit {
                    Text(PanelText.keyRunsOn(macs: macs))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let lastValidated = license.record.lastValidated {
                    Text("Last checked \(lastValidated.formatted(.relative(presentation: .named)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Deactivate this Mac…") { confirmingDeactivate = true }
                        .disabled(license.busy)
                    if license.busy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Manage in Polar") { NSWorkspace.shared.open(license.config.customerPortalURL) }
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
                        Button(PanelText.title(of: .buy)) { NSWorkspace.shared.open(license.config.checkoutURL) }
                    }
                }
                // The portal lists the keys of whoever bought before. The
                // message of a full key has its own link to it.
                if license.record.key == nil, license.message != .limitReached {
                    Link("Bought before? Find your key", destination: license.config.customerPortalURL)
                        .font(.callout)
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
                if message == .revoked {
                    Link("Contact support", destination: AppLinks.contact)
                        .font(.callout)
                }
            }
            if let error = license.storageError {
                Text("\(error.hasSuffix(".") ? error : error + ".") Agent Caffeine keeps your trial and your last license check in its preferences until it can read the Keychain again.")
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
            return "\(PanelText.trialStatus(daysLeft: daysLeft, end: license.trialEnd, now: Date())) \(PanelText.trialThen)"
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

}

/// The tab About: the version, what the app sends, help, and how to
/// remove the app with everything it added.
struct AboutPreferences: View {
    let version: String
    var canCheckForUpdates = false
    /// The agents whose better detection is on.
    var hooksOn: [HookCatalogEntry] = []
    var helperRegistered = false
    /// The skill or the link to the command line tool is on this Mac.
    var agentSetupOn = false
    /// This Mac holds an activation of a key.
    var licensed = false
    var busy = false
    var checkForUpdates: () -> Void = {}
    var showSetup: () -> Void = {}
    var turnOffHooks: ([HookCatalogEntry]) -> Void = { _ in }
    var removeHelper: () -> Void = {}
    var removeAgentSetup: () -> Void = {}
    var deactivate: () -> Void = {}
    var showInFinder: () -> Void = {}
    var quit: () -> Void = {}

    var body: some View {
        Form {
            Section("About") {
                HStack {
                    Text(version)
                    Spacer()
                    Button("Check for updates…", action: checkForUpdates)
                        .disabled(!canCheckForUpdates)
                }
                Text("While it keeps the Mac awake, Agent Caffeine holds a PreventUserIdleSystemSleep assertion, plus PreventSystemSleep, so the Mac stays awake on battery and when plugged in. The display may still sleep. For a closed lid on battery, its helper also turns on the SleepDisabled setting of macOS, and turns it off when Agent Caffeine stops or quits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Agent Caffeine checks caffeinagent.com for updates. It checks your license key with Polar. It sends the key and your Mac's model, and nothing about you or your agents.")
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
                HStack {
                    Button("Show setup again", action: showSetup)
                    Spacer()
                    Button(PanelText.quit, action: quit)
                }
            }
            Section("Help") {
                row("Questions and answers") { Link("Open help", destination: AppLinks.help) }
                row("Contact") { Link(AppLinks.contactAddress, destination: AppLinks.contact) }
            }
            Section("Remove Agent Caffeine") {
                Text("Do these steps before you move Agent Caffeine to the Trash, so nothing of it stays on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                step(
                    hooksOn.isEmpty ? "Better detection is off" : "Turn off better detection for \(hooksOn.map(\.displayName).joined(separator: ", "))",
                    help: "This removes the lines that Agent Caffeine added to the settings files of your agents.",
                    done: hooksOn.isEmpty
                ) { Button("Turn off") { turnOffHooks(hooksOn) } }
                step(
                    helperRegistered ? "Remove the helper" : "The helper is not set up",
                    help: "This removes the background item for a closed lid on battery.",
                    done: !helperRegistered
                ) { Button("Remove", action: removeHelper) }
                step(
                    agentSetupOn ? "Remove the skill and the command agent-caffeine" : "No skill and no command are set up",
                    help: "This removes the skill from the skills folders of your agents, and the link in ~/.local/bin.",
                    done: !agentSetupOn
                ) { Button("Remove", action: removeAgentSetup) }
                step(
                    licensed ? "Deactivate this Mac" : "No license key is active on this Mac",
                    help: "This frees your license key for another Mac.",
                    done: !licensed
                ) { Button("Deactivate…", action: deactivate).disabled(busy) }
                step(
                    "Quit Agent Caffeine and move it to the Trash",
                    help: "The app is in your Applications folder.",
                    done: false
                ) { Button("Show in Finder", action: showInFinder) }
            }
        }
        .formStyle(.grouped)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing()
        }
    }

    /// One step: what to do, and its button until it is done.
    private func step<Action: View>(_ title: String, help: String, done: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            } else {
                action()
            }
        }
    }

    private static let builderURL = URL(
        string: "https://mertbuilds.com/?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=about"
    )!
}

struct GeneralPreferences: View {
    @Binding var mode: AwakeMode
    @Binding var settings: DetectionSettings
    @Binding var showMenuBarIcon: Bool
    var loginItem = LoginItemState.unavailable
    var loginItemError: String?
    var setOpenAtLogin: (Bool) -> Void = { _ in }
    var openLoginItems: () -> Void = {}

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
                    Toggle("Stay reachable while plugged in", isOn: $settings.stayAwakeForRemoteAccess)
                    Text("This is for Claude Code Remote Control, which sends messages from your phone to an agent on your Mac. While your Mac is plugged in and Remote Control is on, your Mac stays awake, even when no agent is working. On battery, choose \"Stay reachable\" in the timer menu to keep your Mac awake for a set time.")
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
                    help: "Other agents do not say when they finish. For those, Agent Caffeine watches for activity, such as a running command, and your Mac stays awake this long after the last of it."
                )
                duration(
                    "While an agent is waiting for you", $settings.waitingHold,
                    help: "Your Mac stays awake this long while an agent is waiting for your answer. After that Agent Caffeine lets it sleep, unless another agent is working."
                )
            }
            Section {
                Toggle(PanelText.openAtLogin, isOn: Binding(get: { loginItem.isOn }, set: setOpenAtLogin))
                    .disabled(loginItem == .unavailable)
                switch loginItem {
                case .on, .off:
                    Text("Agent Caffeine starts when you log in, so it also runs after a restart of your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .needsApproval:
                    HStack {
                        Text("Allow Agent Caffeine in System Settings > General > Login Items to open it at login.")
                            .font(.callout)
                        Spacer()
                        Button("Open System Settings", action: openLoginItems)
                    }
                case .unavailable:
                    Text(PanelText.moveToApplicationsToUse)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Show Agent Caffeine in the menu bar", isOn: $showMenuBarIcon)
                Text("When hidden, open Agent Caffeine again from Applications or Spotlight to see this window.")
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
    /// Notifications are switched off for Agent Caffeine in System Settings.
    var denied = false
    var history: [AgentNoticeHistory.Entry] = []
    var batteryFloorEnabled = true
    var openSystemSettings: () -> Void = {}

    var body: some View {
        Form {
            if denied {
                Section {
                    HStack {
                        Label("Notifications are off for Agent Caffeine in System Settings", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings", action: openSystemSettings)
                    }
                }
            }
            Section("Notify me when") {
                toggle(
                    "An agent is waiting for you", $notices.waiting,
                    help: "You get a notification when an agent asks you a question or needs your permission."
                )
                toggle(
                    "An agent finished", $notices.finished,
                    help: "You get a notification when an agent finishes its work."
                )
            }
            Section {
                toggle(
                    "Only notify when the agent's window is not in front", $notices.onlyWhenAway,
                    help: "You get no notification while you use the app the agent runs in."
                )
                .disabled(!notices.wantsAny)
            }
            if !history.isEmpty {
                Section("Last notifications") {
                    ForEach(history) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.title)
                                Spacer()
                                Text(entry.at, style: .time)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(entry.result.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text(SafetyText.alwaysTold(batteryFloorEnabled: batteryFloorEnabled))
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
    var choices = ShortcutChoices()
    var shortcutProblems: [ShortcutAction: ShortcutProblem] = [:]
    var setShortcut: (Shortcut?, ShortcutAction) -> Void = { _, _ in }
    var resetShortcut: (ShortcutAction) -> Void = { _ in }
    var setShortcutRecording: (Bool) -> Void = { _ in }

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRecorder(
                        title: action.title, shortcut: choices.shortcuts[action], problem: shortcutProblems[action],
                        set: { setShortcut($0, action) }, reset: choices.isChanged(action) ? { resetShortcut(action) } : nil,
                        setRecording: setShortcutRecording
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
    /// The menu asked for "Other tools": the tab scrolls there once.
    var showsOtherTools: Binding<Bool> = .constant(false)
    /// The tool in the copy of the app that runs.
    var commandLine = CommandLineSetup(appPath: Bundle.main.bundleURL.standardizedFileURL.path)
    var agentSetup = AgentSetupModel()
    var setUpForAgents: () -> Void = {}
    var installSkill: (SkillCatalogEntry) -> Void = { _ in }
    var linkTool: () -> Void = {}
    var removeAgentSetup: () -> Void = {}
    @State private var newName = ""

    private static let otherToolsID = "otherTools"

    /// A definition without matchers is a placeholder that finds nothing.
    private static let definitions = AgentCatalog.standard.definitions.filter { !$0.matchers.isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { showOtherTools(proxy) }
                .onChange(of: showsOtherTools.wrappedValue) { _ in showOtherTools(proxy) }
        }
    }

    /// After the layout, or there is nothing to scroll to yet.
    private func showOtherTools(_ proxy: ScrollViewProxy) {
        guard showsOtherTools.wrappedValue else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(Self.otherToolsID, anchor: .top)
            showsOtherTools.wrappedValue = false
        }
    }

    private var form: some View {
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
                Text("Agents marked Not tested yet are found by name. Agent Caffeine sees them as working while they use the processor or run a command.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(Self.definitions.filter { !foundIDs.contains($0.id) }, id: \.id, content: row)
            }
            Section("Other tools") {
                Text("Add a tool that is not in the list by its process name: the name of the command you type in Terminal to start the tool, for example aider. It counts as working while it is using the processor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .id(Self.otherToolsID)
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
                    TextField("Process name", text: $newName, prompt: Text("Process name, for example aider"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            CommandLinePreferencesSection(
                setup: commandLine, agentSetup: agentSetup, setUpForAgents: setUpForAgents, installSkill: installSkill,
                linkTool: linkTool, removeAgentSetup: removeAgentSetup
            )
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
    /// The fade is offered only on a Mac with a lid angle sensor.
    var hasLidAngleSensor = false
    let error: String?
    let setUp: () -> Void
    let remove: () -> Void
    var tryAgain: () -> Void = {}
    let openLoginItems: () -> Void
    let removeSudoersEntry: () -> Void
    var playChime: () -> Void = {}
    @State private var confirmingFloorOff = false

    /// Off waits for the answer to the question. On is set at once.
    private var batteryFloorSwitch: Binding<Bool> {
        Binding {
            settings.batteryFloorEnabled
        } set: { enabled in
            if settings.needsConfirmation(toSetBatteryFloor: enabled) {
                confirmingFloorOff = true
            } else {
                settings.batteryFloorEnabled = enabled
            }
        }
    }

    var body: some View {
        Form {
            Section("Battery limit") {
                Toggle("Let your Mac sleep when the battery is low", isOn: batteryFloorSwitch)
                Stepper(value: $settings.batteryFloorPercent, in: DetectionSettings.batteryFloorRange, step: 5) {
                    Text("Sleep at \(PanelText.percent(settings.batteryFloorPercent))")
                }
                .disabled(!settings.batteryFloorEnabled)
                Group {
                    if settings.batteryFloorEnabled {
                        Text(SafetyText.floorOnHelp)
                        Text("Agent Caffeine also lets your Mac sleep when it gets too hot.")
                    } else {
                        Label(SafetyText.floorOffWarning, systemImage: "exclamationmark.triangle")
                        Text("Agent Caffeine still lets your Mac sleep when it gets too hot.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section("Lid closed") {
                Group {
                    Text(PanelText.lidClosedExplained)
                    Text("\(PanelText.helperExplained) \(PanelText.helperRemoveHere)")
                    Text(PanelText.closedBagWarning)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                helperState
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Stay awake with the lid closed on battery", isOn: $settings.stayAwakeLidClosedOnBattery)
                    .disabled(helper != .enabled)
                if helper != .enabled {
                    Text("Set up the helper first.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle("Turn the display off when the lid is closed", isOn: $settings.displayOffLidClosed)
                Text("With the lid closed, Agent Caffeine keeps the built-in display dark so it does not use the battery or warm your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if hasLidAngleSensor {
                    Toggle("Dim the display as the lid closes", isOn: $settings.dimAsLidCloses)
                        .disabled(!settings.displayOffLidClosed)
                    Text("The built-in display gets darker from 45 degrees and is off when the lid is closed. It gets bright again the same way when you open the lid. A lid that rests half open stays bright.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle(PanelText.lidChimeSwitch, isOn: $settings.chimeOnLidClose)
                LabeledContent("Sound") {
                    HStack {
                        Picker("Sound", selection: $settings.lidChimeSound) {
                            ForEach(LidChimeSound.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Play", action: playChime)
                    }
                }
                .disabled(!settings.chimeOnLidClose)
                Text(PanelText.lidChimeExplained)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if needsSudoersCleanup {
                Section {
                    Text("An older version of Agent Caffeine added an admin entry to this Mac. It is no longer used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Remove the old admin entry…", action: removeSudoersEntry)
                }
            }
        }
        .formStyle(.grouped)
        .alert(SafetyText.floorOffQuestion, isPresented: $confirmingFloorOff) {
            Button("Keep the limit", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Turn the limit off") { settings.batteryFloorEnabled = false }
        } message: {
            Text(SafetyText.floorOffConsequence)
        }
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
                Label(PanelText.helperIsSetUp, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Remove", action: remove)
            }
        case .requiresApproval:
            HStack {
                Text(PanelText.allowInLoginItems)
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
                Text(PanelText.moveToApplicationsToSetUp)
            }
        case .notSetUp:
            if canSetUp {
                Button("Set up…", action: setUp)
            } else {
                Text(PanelText.moveToApplicationsToSetUp)
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
                .tabItem { Label("Notifications", systemImage: "bell") }
            ShortcutPreferences()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AgentPreferences(
                settings: $settings, foundIDs: ["claude", "codex-desktop"],
                hookRows: HookRowModel.rows(statuses: ["claude": .installed(version: 1), "codex": .outdated, "droid": .notInstalled]),
                agentSetup: AgentSetupModel(snapshot: SkillSnapshot(
                    agents: SkillCatalog.entries.prefix(3).map { SkillSnapshot.Agent(entry: $0, status: .notInstalled) },
                    planned: [".claude/skills", ".agents/skills"]
                ))
            )
                .tabItem { Label("Agents", systemImage: "terminal") }
            LidClosedPreferences(
                settings: $settings, helper: helper, setup: setup, repairTried: true, canSetUp: true, needsSudoersCleanup: needsSudoersCleanup,
                hasLidAngleSensor: true, error: nil,
                setUp: {}, remove: {}, openLoginItems: {}, removeSudoersEntry: {}
            )
            .tabItem { Label("Battery and lid", systemImage: "laptopcomputer") }
            AboutPreferences(version: "1.0 (1)", hooksOn: HookCatalog.entries.prefix(2).map { $0 }, helperRegistered: true, licensed: true)
                .tabItem { Label("About", systemImage: "info.circle") }
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
