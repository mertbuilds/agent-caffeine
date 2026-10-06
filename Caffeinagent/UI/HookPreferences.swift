import SwiftUI

/// One agent's hooks as Preferences and the setup window show them.
struct HookRowModel: Equatable, Identifiable {
    let entry: HookCatalogEntry
    var status: HookStatus
    /// What went wrong the last time, in plain words.
    var error: String?

    var id: String { entry.id }

    var isOn: Bool {
        switch status {
        case .installed, .outdated: return true
        case .notInstalled, .configMissing, .unreadable: return false
        }
    }

    /// Turning on needs the hook command in the Applications folder.
    /// Turning off needs nothing but a file that can be read.
    static func toggleDisabled(_ row: HookRowModel, available: Bool) -> Bool {
        row.status == .unreadable || (!available && !row.isOn)
    }

    /// The rows of the agents that are set up on this Mac.
    static func rows(statuses: [String: HookStatus], errors: [String: String] = [:]) -> [HookRowModel] {
        HookCatalog.entries.compactMap { entry in
            guard let status = statuses[entry.id], status != .configMissing else { return nil }
            return HookRowModel(entry: entry, status: status, error: errors[entry.id])
        }
    }
}

/// The "Better detection" section of Preferences > Agents.
struct HookPreferencesSection: View {
    let rows: [HookRowModel]
    /// False when the hook command is not in the Applications folder.
    let available: Bool
    let set: (HookCatalogEntry, Bool) -> Void

    var body: some View {
        Section("Better detection") {
            Text("An agent can tell agent caffeine what it is doing. To make that work, agent caffeine adds a few lines to the agent's settings file. It never reads what you type.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !available {
                Text("Move agent caffeine to the Applications folder to use this")
                    .font(.callout)
            }
            ForEach(rows) { row in
                HookRow(row: row, available: available) { set(row.entry, $0) }
            }
        }
    }
}

struct HookRow: View {
    let row: HookRowModel
    let available: Bool
    let set: (Bool) -> Void
    @State private var showsChanges = false

    private var path: String { "~/" + row.entry.configPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(row.entry.displayName, isOn: Binding(get: { row.isOn }, set: set))
                // Off is always possible: it only takes our lines out.
                .disabled(HookRowModel.toggleDisabled(row, available: available))
            Text(row.entry.benefit)
                .font(.callout)
                .foregroundStyle(.secondary)
            switch row.status {
            case .outdated:
                HStack {
                    Text("These lines are from another version of agent caffeine")
                        .font(.callout)
                    Spacer()
                    Button("Update") { set(true) }
                        .disabled(!available)
                }
            case .installed:
                if let note = row.entry.afterInstall {
                    Text(note).font(.callout)
                }
            case .unreadable:
                Text(HookInstallError.unreadable.message(file: path))
                    .font(.callout)
            case .notInstalled, .configMissing:
                EmptyView()
            }
            if let error = row.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            DisclosureGroup("Show what changes", isExpanded: $showsChanges) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(changeSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Text(HookConfigEditor.preview(for: row.entry, appPath: HookCatalog.stableAppPath))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
    }

    private var changeSummary: String {
        switch row.entry.format {
        case .pluginFile:
            return "agent caffeine writes this file: \(path). Switching this off removes the file."
        case .jsonHookGroups:
            return "agent caffeine adds these lines to \(path) and saves a copy of the file next to it first. Switching this off removes the lines and nothing else. If agent caffeine created the file and nothing else is in it, the file is removed too."
        }
    }
}
