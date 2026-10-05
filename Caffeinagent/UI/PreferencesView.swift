import SwiftUI

enum PreferencesTab: Hashable {
    case general
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
            GeneralPreferences(mode: $aggregator.mode, settings: $aggregator.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)
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
                canSetUp: aggregator.canSetUpHelper,
                needsSudoersCleanup: aggregator.sleepFlag.needsSudoersCleanup,
                error: aggregator.helperError,
                setUp: aggregator.setUpHelper,
                remove: aggregator.removeHelper,
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
                Text("Built by")
                    .foregroundStyle(.secondary)
                Link("mertbuilds.com", destination: Self.builderURL)
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
                    Text("The key becomes free for another Mac. agent caffeine stops keeping this Mac awake until a key is activated again.")
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
                Text("\(error) agent caffeine keeps your trial and your last license check in its preferences until it can read the Keychain again.")
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
            return "Trial: \(daysLeft) \(daysLeft == 1 ? "day" : "days") left"
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

    /// From 30 seconds to 30 minutes.
    private static let durations: [TimeInterval] = [30, 60, 120, 180, 300, 600, 900, 1200, 1800]

    var body: some View {
        Form {
            Section("Keep the Mac awake") {
                Picker("Keep the Mac awake", selection: $mode) {
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
                    Toggle("Stay awake on power while phone access is on", isOn: $settings.stayAwakeForRemoteAccess)
                    Text("For Claude Code Remote Control. While the Mac is on power and Remote Control is on, the Mac stays awake, also when no agent works.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Let the Mac sleep after") {
                duration(
                    "An agent finishes", $settings.releaseAfterState,
                    help: "Claude Code and Codex tell when they finish. The Mac stays awake this long after that, so a short break between two tasks does not let it sleep."
                )
                duration(
                    "The last sign of work", $settings.releaseAfterActivity,
                    help: "For agents that do not report their state. agent caffeine looks for signs of work, such as a running command, and waits this long after the last one."
                )
                duration(
                    "An agent waits for you", $settings.waitingHold,
                    help: "The Mac stays awake this long while an agent waits for your answer."
                )
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
            Section("Found on this Mac now") {
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
                Text("Add the process name of a tool that is not in the list. It counts as working while it uses the processor.")
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
                Text("not tested yet")
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
        case .alwaysWorkingWhileOpen: return "Always counts as working while open"
        case .ignore: return "Ignore"
        }
    }
}

struct LidClosedPreferences: View {
    @Binding var settings: DetectionSettings
    let helper: HelperStatus
    /// The helper is offered only from the Applications folder.
    let canSetUp: Bool
    let needsSudoersCleanup: Bool
    let error: String?
    let setUp: () -> Void
    let remove: () -> Void
    let openLoginItems: () -> Void
    let removeSudoersEntry: () -> Void

    var body: some View {
        Form {
            Section("Lid closed") {
                Text("On battery, macOS puts the Mac to sleep when you close the lid, also while an agent works. agent caffeine can stop that with a small helper that you allow one time.")
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
                    Text("Let the Mac sleep under \(settings.batteryFloorPercent) percent battery")
                }
                Text("agent caffeine also lets the Mac sleep when it gets too hot")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if needsSudoersCleanup {
                Section {
                    Text("An older version of agent caffeine added an admin entry to this Mac. It is no longer used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Remove old admin entry", action: removeSudoersEntry)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var helperState: some View {
        switch helper {
        case .enabled:
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
        case .notRegistered, .notFound:
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
    var needsSudoersCleanup = false
    @State private var mode = AwakeMode.agentWorking
    @State private var settings = DetectionSettings()

    var body: some View {
        TabView {
            GeneralPreferences(mode: $mode, settings: $settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AgentPreferences(
                settings: $settings, foundIDs: ["claude", "codex-desktop"],
                hookRows: HookRowModel.rows(statuses: ["claude": .installed(version: 1), "codex": .outdated, "droid": .notInstalled])
            )
                .tabItem { Label("Agents", systemImage: "terminal") }
            LidClosedPreferences(
                settings: $settings, helper: helper, canSetUp: true, needsSudoersCleanup: needsSudoersCleanup, error: nil,
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
    PreferencesPreview(helper: .enabled, needsSudoersCleanup: true)
}

#Preview("Helper waits for approval") {
    PreferencesPreview(helper: .requiresApproval)
}
#endif
