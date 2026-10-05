import SwiftUI

struct PreferencesView: View {
    @ObservedObject var aggregator: StateAggregator
    @State private var newEntry: String = ""

    var body: some View {
        Form {
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
                Text("While it keeps the Mac awake, agent caffeine holds a PreventUserIdleSystemSleep assertion, plus PreventSystemSleep, so the Mac stays awake on battery and when plugged in. The display may still sleep. On battery, it also turns on `pmset -b disablesleep` through sudo if you installed the sudoers entry above.")
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
        .frame(width: 440, height: 600)
        .tint(.brand)
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
