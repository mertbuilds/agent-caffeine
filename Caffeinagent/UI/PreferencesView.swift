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
            Section("about") {
                Text("caffeinagent holds an IOPMAssertPreventSystemSleep while an agent is active. on AC power this keeps the mac awake even with the lid closed. on battery, macos clamshell-sleeps regardless — this is an OS-level limit.")
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
