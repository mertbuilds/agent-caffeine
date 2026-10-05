import SwiftUI

struct PreferencesView: View {
    @ObservedObject var aggregator: StateAggregator
    @ObservedObject var updater: Updater
    @State private var newEntry: String = ""
    @State private var licenseKey: String = ""
    @State private var confirmingDeactivate = false

    private var license: LicenseManager { aggregator.license }

    var body: some View {
        Form {
            licenseSection
            Section("Keep the Mac awake") {
                Picker("Keep the Mac awake", selection: $aggregator.mode) {
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
            Section("Agents") {
                Text("agent caffeine looks for these processes. An agent counts as working while it, or a command it started, uses the CPU, and as idle while it waits at its prompt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                List {
                    ForEach(aggregator.processes.allowlist, id: \.self) { name in
                        HStack {
                            Text(name).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(role: .destructive) { remove(name) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 140)
                HStack {
                    TextField("Process name, for example codex", text: $newEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore defaults") {
                    aggregator.processes.allowlist = ProcessWatcher.defaultAllowlist
                }
                .buttonStyle(.borderless)
            }
            Section("Battery") {
                if aggregator.battery.sudoersInstalled {
                    Label("Installed. agent caffeine turns on the pmset override automatically on battery.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Uninstall sudoers entry…") { aggregator.battery.uninstall() }
                } else {
                    Text("On battery, macOS sleeps the Mac when you close the lid, even while agent caffeine is active. Install a sudoers entry to let agent caffeine run `pmset -b disablesleep` without asking for your password each time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Install sudoers entry…") { aggregator.battery.install() }
                }
                if let err = aggregator.battery.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Note: on Apple silicon, `pmset disablesleep` does not always prevent clamshell sleep. If your Mac still sleeps on battery with the lid closed, the override did not hold. Keep the lid open as a fallback.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("About") {
                HStack {
                    Text(AppVersion.current)
                    Spacer()
                    Button("Check for updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                Text("While it keeps the Mac awake, agent caffeine holds a PreventUserIdleSystemSleep assertion, plus PreventSystemSleep, so the Mac stays awake on battery and when plugged in. The display may still sleep. On battery, it also turns on `pmset -b disablesleep` through sudo if you installed the sudoers entry above.")
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 680)
        .tint(.brand)
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

    private func add() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aggregator.processes.allowlist.contains(trimmed) else { return }
        aggregator.processes.allowlist = aggregator.processes.allowlist + [trimmed]
        newEntry = ""
    }

    private func remove(_ name: String) {
        aggregator.processes.allowlist = aggregator.processes.allowlist.filter { $0 != name }
    }
}
