import SwiftUI

struct PreferencesView: View {
    @ObservedObject var aggregator: StateAggregator
    @State private var newEntry: String = ""

    var body: some View {
        Form {
            Section("CLI allowlist") {
                Text("processes whose presence keeps the mac awake")
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
                    TextField("process name (e.g. codex)", text: $newEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("add", action: add)
                        .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("restore defaults") {
                    aggregator.processes.allowlist = ProcessWatcher.defaultAllowlist
                }
                .buttonStyle(.borderless)
            }
            Section("battery override") {
                if aggregator.battery.sudoersInstalled {
                    Label("installed — pmset toggled automatically when on battery",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("uninstall sudoers entry…") { aggregator.battery.uninstall() }
                } else {
                    Text("by default, macos sleeps the mac when the lid closes on battery — even with caffeinagent active. install a sudoers entry to let caffeinagent run `pmset -b disablesleep` without a password prompt every time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("install sudoers entry…") { aggregator.battery.install() }
                }
                if let err = aggregator.battery.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("note: on Apple Silicon, `pmset disablesleep` doesn't always beat clamshell sleep. if your mac still sleeps on battery with the lid closed, the override didn't survive — keep the lid open as a fallback.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("about") {
                Text("holds an IOPMAssertPreventSystemSleep while an agent is active; on AC this keeps the mac awake with the lid closed. on battery, also toggles `pmset -b disablesleep` via sudo if you've installed the sudoers entry above.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
    }

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
