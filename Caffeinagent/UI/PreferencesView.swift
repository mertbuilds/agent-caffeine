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
                setOpenAtLogin: aggregator.setOpenAtLogin, openLoginItems: aggregator.sleepFlag.openLoginItemsSettings,
                hotspot: HotspotPreferences(
                    hotspot: aggregator.hotspot, autoJoin: aggregator.hotspotAutoJoin,
                    offersAutomatic: HotspotSystemSettings.offersAutomatic,
                    setOn: aggregator.setHotspotOn, setHopBack: aggregator.setHotspotHopBack, save: aggregator.saveHotspot,
                    openPrivacy: aggregator.openLocationSettings, openWiFi: aggregator.openWiFiSettings
                )
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
                playChime: aggregator.playLidChime,
                jobSettings: $aggregator.jobSettings,
                jobWake: aggregator.jobWake,
                closeJobSwitchNotice: aggregator.closeJobSwitchNotice
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
                hotspotSaved: aggregator.hotspot.somethingSaved,
                licensed: license.record.activationID != nil,
                busy: license.busy,
                checkForUpdates: updater.checkForUpdates,
                showSetup: { OnboardingWindow.show(aggregator: aggregator) },
                turnOffHooks: { $0.forEach { aggregator.setHooks($0, on: false) } },
                removeHelper: aggregator.removeHelper,
                removeAgentSetup: aggregator.removeAgentSetup,
                forgetHotspot: aggregator.forgetHotspot,
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
            aggregator.refreshJobs()
            aggregator.refreshHotspot()
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
                if let end = license.updatesEnd {
                    Text(PanelText.updates(until: end, now: Date()))
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
            } else if license.keyTooOldForThisBuild, let end = license.updatesEnd {
                Text(LicenseRules.coveredUntil(end))
                    .foregroundStyle(.orange)
                Text(PanelText.olderVersionsKeepWorking)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if case .trial = aggregator.entitlement {
                    Text(licenseStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                TextField("New license key", text: $licenseKey, prompt: Text("AGENTCAF-…"))
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
                    Button(PanelText.buyNewKey) { NSWorkspace.shared.open(license.config.checkoutURL) }
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
    /// "Join your iPhone hotspot" is on: a name is in the settings or a
    /// password in the Keychain.
    var hotspotSaved = false
    /// This Mac holds an activation of a key.
    var licensed = false
    var busy = false
    var checkForUpdates: () -> Void = {}
    var showSetup: () -> Void = {}
    var turnOffHooks: ([HookCatalogEntry]) -> Void = { _ in }
    var removeHelper: () -> Void = {}
    var removeAgentSetup: () -> Void = {}
    var forgetHotspot: () -> Void = {}
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
                Text("Checks caffeinagent.com for updates, and your license key with Polar. Sends the key and your Mac's model, and nothing about you or your agents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("How it keeps your Mac awake")
                    Spacer()
                    InfoButton(text: "While it keeps the Mac awake, Agent Caffeine holds a PreventUserIdleSystemSleep assertion, plus PreventSystemSleep, so the Mac stays awake on battery and when plugged in. The display may still sleep. For a closed lid on battery, its helper also turns on the SleepDisabled setting of macOS, and turns it off when Agent Caffeine stops or quits. With Wake for jobs on, the helper also keeps one wake time in the schedule of macOS, and takes it away when Agent Caffeine quits.")
                }
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
            if let notices = AppLinks.acknowledgements {
                Section(PanelText.acknowledgements) {
                    row(PanelText.thirdPartyNotices) {
                        Button(PanelText.openNotices) { NSWorkspace.shared.open(notices) }
                    }
                }
            }
            Section("Help") {
                row("Questions and answers") { Link("Open help", destination: AppLinks.help) }
                row("Contact") { Link(AppLinks.contactAddress, destination: AppLinks.contact) }
            }
            Section("Remove Agent Caffeine") {
                Text("Do these steps before you move the app to the Trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                step(
                    hooksOn.isEmpty ? "Better detection is off" : "Turn off better detection for \(hooksOn.map(\.displayName).joined(separator: ", "))",
                    info: "Removes the lines Agent Caffeine added to the settings files of your agents.",
                    done: hooksOn.isEmpty
                ) { Button("Turn off") { turnOffHooks(hooksOn) } }
                step(
                    helperRegistered ? "Remove the helper" : "The helper is not set up",
                    info: "Removes the background item for a closed lid on battery.",
                    done: !helperRegistered
                ) { Button("Remove", action: removeHelper) }
                step(
                    agentSetupOn ? "Remove the skill and the agent-caffeine command" : "No skill and no command are set up",
                    info: "Removes the skill from the skills folders of your agents, and the link in ~/.local/bin.",
                    done: !agentSetupOn
                ) { Button("Remove", action: removeAgentSetup) }
                step(
                    PanelText.hotspotRemoveStep(saved: hotspotSaved),
                    info: PanelText.hotspotRemoveHelp,
                    done: !hotspotSaved
                ) { Button("Forget", action: forgetHotspot) }
                step(
                    licensed ? "Deactivate this Mac" : "No license key is active on this Mac",
                    info: "Frees your license key for another Mac.",
                    done: !licensed
                ) { Button("Deactivate…", action: deactivate).disabled(busy) }
                step("Move Agent Caffeine to the Trash", done: false) { Button("Show in Finder", action: showInFinder) }
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
    private func step<Action: View>(_ title: String, info: String? = nil, done: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Text(title)
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            } else {
                action()
            }
            if let info { InfoButton(text: info) }
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
    /// "iPhone hotspot (Beta)", below the offline rule.
    var hotspot = HotspotPreferences()

    /// From 30 seconds to 30 minutes.
    private static let durations: [TimeInterval] = [30, 60, 120, 180, 300, 600, 900, 1200, 1800]

    var body: some View {
        Form {
            Section("Keep your Mac awake") {
                Picker("Keep your Mac awake", selection: $mode) {
                    ForEach(AwakeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Text(mode.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !RemoteAccessDetector.detectedTools.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle("Stay reachable while plugged in", isOn: $settings.stayAwakeForRemoteAccess)
                            InfoButton(text: "Remote Control sends messages from your phone to an agent on your Mac. While your Mac is plugged in and Remote Control is on, your Mac stays awake, even when no agent works. On battery, use Stay reachable in the timer menu.")
                        }
                        Text("For Claude Code Remote Control")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Stay awake") {
                duration(
                    "After an agent finishes", $settings.releaseAfterState,
                    info: "Claude Code and Codex say when they finish. This time covers a short break between two tasks."
                )
                duration(
                    "After other agents go quiet", $settings.releaseAfterActivity,
                    info: "Other agents do not say when they finish. Agent Caffeine waits this long after their last activity, such as a running command."
                )
                duration(
                    "While an agent waits for you", $settings.waitingHold,
                    info: "After this time your Mac can sleep, unless another agent is working."
                )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Picker(PanelText.offlineLimitPicker, selection: $settings.offlineLimitMinutes) {
                            ForEach(OfflineRule.minuteChoices, id: \.self) { Text(HumaneDuration.counted($0, "minute")).tag($0) }
                            Text(PanelText.never).tag(OfflineRule.never)
                        }
                        InfoButton(text: PanelText.offlineLimitInfo)
                    }
                    Text(PanelText.offlineLimitExplained)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            hotspot
            Section {
                Toggle(PanelText.openAtLogin, isOn: Binding(get: { loginItem.isOn }, set: setOpenAtLogin))
                    .disabled(loginItem == .unavailable)
                switch loginItem {
                case .on, .off:
                    EmptyView()
                case .needsApproval:
                    HStack {
                        Text("Allow in System Settings > Login Items.")
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
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                Text("When hidden, open Agent Caffeine from Applications to come back here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func duration(_ title: String, _ value: Binding<TimeInterval>, info: String) -> some View {
        HStack {
            Picker(title, selection: value) {
                // A value that is not on the list stays selectable.
                ForEach(Set(Self.durations + [value.wrappedValue]).sorted(), id: \.self) {
                    Text(Self.text(for: $0)).tag($0)
                }
            }
            InfoButton(text: info)
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
                        Label("Notifications are off in System Settings", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings", action: openSystemSettings)
                    }
                }
            }
            Section("Notify me when") {
                Toggle("An agent waits for you", isOn: $notices.waiting)
                Toggle("An agent finishes", isOn: $notices.finished)
            }
            Section {
                Toggle("Only when its app is not in front", isOn: $notices.onlyWhenAway)
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
                Text("Works in every app. Click a field, then press the keys.")
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
    /// The menu asked for "Add a tool": the tab scrolls there once.
    var showsOtherTools: Binding<Bool> = .constant(false)
    /// The tool in the copy of the app that runs.
    var commandLine = CommandLineSetup(appPath: AppInstall.running.path)
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
            AgentSetupSection(
                model: agentSetup, commandLine: commandLine, setUp: setUpForAgents, install: installSkill,
                link: linkTool, remove: removeAgentSetup
            )
            Section("Open now") {
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
                HStack {
                    Text("Not tested yet means found by name only")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    InfoButton(text: "Agent Caffeine counts these as working while they use the processor or run a command.")
                }
                ForEach(Self.definitions.filter { !foundIDs.contains($0.id) }, id: \.id, content: row)
            }
            Section("Add a tool") {
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
                    TextField("Command name", text: $newName, prompt: Text("Command name, for example aider"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    InfoButton(text: "The name you type in Terminal to start the tool. It counts as working while it uses the processor.")
                }
                .id(Self.otherToolsID)
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
        case .alwaysWorkingWhileOpen: return "Always working"
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
    var jobSettings: Binding<JobSettings> = .constant(JobSettings())
    var jobWake = JobWakeView()
    var closeJobSwitchNotice: () -> Void = {}
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
                Toggle("Sleep when the battery is low", isOn: batteryFloorSwitch)
                Stepper(value: $settings.batteryFloorPercent, in: DetectionSettings.batteryFloorRange, step: 5) {
                    Text("Sleep at \(PanelText.percent(settings.batteryFloorPercent))")
                }
                .disabled(!settings.batteryFloorEnabled)
                Group {
                    if settings.batteryFloorEnabled {
                        Text(SafetyText.floorOnHelp)
                    } else {
                        HStack {
                            Label(SafetyText.floorOffWarning, systemImage: "exclamationmark.triangle")
                            Spacer()
                            InfoButton(text: SafetyText.floorOffLidClosed)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Section("Closed lid on battery") {
                Picker(PanelText.closedLidLimitPicker, selection: $settings.closedLidLimitHours) {
                    ForEach(ClosedLidLimit.hourChoices, id: \.self) { Text(HumaneDuration.counted($0, "hour")).tag($0) }
                    Text(PanelText.noLimit).tag(ClosedLidLimit.noLimit)
                }
                Picker("Or until the battery drops by", selection: $settings.closedLidLimitDrop) {
                    ForEach(ClosedLidLimit.dropChoices, id: \.self) { Text(PanelText.percent($0)).tag($0) }
                    Text(PanelText.noLimit).tag(ClosedLidLimit.noLimit)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(PanelText.closedLidLimitExplained)
                    Text(PanelText.closedLidLimitExceptions)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Toggle("Stay awake with the lid closed", isOn: $settings.stayAwakeLidClosedOnBattery)
                    .disabled(helper != .enabled)
                if helper != .enabled {
                    Text("Set up the helper first")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                helperState
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Label(PanelText.closedBagWarningInSettings, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                HStack {
                    Toggle("Turn off the display", isOn: $settings.displayOffLidClosed)
                    InfoButton(text: "Keeps the built-in display dark with the lid closed, to save battery and heat.")
                }
                if hasLidAngleSensor {
                    HStack {
                        Toggle("Dim as the lid closes", isOn: $settings.dimAsLidCloses)
                            .disabled(!settings.displayOffLidClosed)
                        InfoButton(text: "The display gets darker from 45 degrees and turns off when the lid closes. Your brightness comes back when you open the lid. A lid that rests half open stays bright.")
                    }
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
            WakeForJobsSection(settings: jobSettings, view: jobWake, closeSwitchNotice: closeJobSwitchNotice)
            if needsSudoersCleanup {
                Section {
                    Text("An older version added an admin entry. It is no longer used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Remove old admin entry…", action: removeSudoersEntry)
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
            Label("Cannot reach the helper. Your Mac sleeps when you close the lid on battery.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            HStack {
                Button(PanelText.title(of: .tryHelperAgain), action: tryAgain)
                if repairTried {
                    Button(PanelText.title(of: .openLoginItems), action: openLoginItems)
                }
            }
        case .ready:
            HStack {
                Text("Helper")
                Spacer()
                Label("Set up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Remove", action: remove)
                InfoButton(text: PanelText.helperInfo)
            }
        case .requiresApproval:
            HStack {
                Text("Allow Agent Caffeine in System Settings > Login Items")
                Spacer()
                Button("Open System Settings", action: openLoginItems)
            }
        case .lost:
            if canSetUp {
                HStack {
                    Text("Set up the helper again")
                    Spacer()
                    Button("Set up…", action: setUp)
                }
            } else {
                Text(PanelText.moveToApplicationsToSetUp)
            }
        case .notSetUp:
            HStack {
                Text("Helper")
                Spacer()
                if canSetUp { Button("Set up…", action: setUp) }
                InfoButton(text: PanelText.helperInfo)
            }
            if !canSetUp {
                Text(PanelText.moveToApplicationsToSetUp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
