import AppKit
import SwiftUI

/// "Set up for agents" as Settings and the setup window show it: the
/// skill per agent, the link to the tool, and what the button would do.
struct AgentSetupModel: Equatable {
    var snapshot = SkillSnapshot()
    /// What went wrong the last time, in plain words, by agent id and
    /// `SkillInstaller.linkKey`.
    var errors: [String: String] = [:]
    /// Nil when it is not known. See `ShellPath`.
    var localBinOnPath: Bool?
    /// "~/.zshrc": where a line for the PATH goes. Nil for a shell we do not know.
    var startupFile: String?
    /// False when the skill is not in the bundle.
    var available = true

    /// The agents the button would add the skill for.
    var pending: [SkillCatalogEntry] {
        snapshot.agents.filter { $0.status == .notInstalled || isOutdated($0.status) }.map(\.entry)
    }

    private func isOutdated(_ status: SkillAgentStatus) -> Bool {
        if case .outdated = status { return true }
        return false
    }

    var isLinked: Bool {
        if case .ours = snapshot.link { return true }
        return false
    }

    /// Nothing is there, or a link of ours to a copy that is gone.
    private var linkIsMissing: Bool { [.none, .dead].contains(snapshot.link) }

    /// The link can be made, and this copy of the app may make it.
    var canLink: Bool { snapshot.linkAllowed && linkIsMissing }

    /// The line in place of the offer to link, for a copy of the app that
    /// does not run from the Applications folder.
    var linkNote: String? {
        !snapshot.linkAllowed && linkIsMissing ? PanelText.commandLinkNeedsApplications : nil
    }

    /// Something of ours is on this Mac, so the rows and "Remove" are shown.
    var isSetUp: Bool {
        isLinked || snapshot.agents.contains { status in
            switch status.status {
            case .installed, .outdated: return true
            case .notInstalled, .foreign: return false
            }
        }
    }

    /// The setup window offers the step while an agent has no skill.
    var isOffered: Bool { available && !pending.isEmpty }

    var summary: String? {
        PanelText.agentSetupSummary(agents: pending.map(\.displayName), links: canLink)
    }

    /// What the button writes, as paths with `~`.
    var changes: [String] {
        snapshot.planned.map { "~/\($0)/\(SkillCatalog.skillName)/\(SkillCatalog.fileName)" } + (canLink ? ["~/" + SkillInstaller.linkPath] : [])
    }

    var pathHint: String? {
        guard isLinked, localBinOnPath == false, let startupFile else { return nil }
        return PanelText.localBinNotOnPath(file: startupFile)
    }

    /// The errors that belong to no row.
    var otherErrors: [String] {
        let rows = Set(snapshot.agents.map(\.id) + [SkillInstaller.linkKey])
        return errors.filter { !rows.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
    }

    // MARK: Rows

    static func folder(_ place: String) -> String {
        "~/\(place)/\(SkillCatalog.skillName)"
    }

    static func detail(_ status: SkillAgentStatus) -> String {
        switch status {
        case .notInstalled: return PanelText.skillNotInstalled
        case .installed(let place): return PanelText.skillInstalled(in: folder(place))
        case .outdated(let place): return PanelText.skillOutdated(in: folder(place))
        case .foreign(let place): return PanelText.skillForeign(folder(place))
        }
    }

    /// "Install" for an agent that came to the Mac later, "Update" for a
    /// skill of an older build.
    static func action(_ status: SkillAgentStatus) -> String? {
        switch status {
        case .notInstalled: return "Install"
        case .outdated: return "Update"
        case .installed, .foreign: return nil
        }
    }

    var linkDetail: String {
        switch snapshot.link {
        case .ours: return PanelText.commandLinked
        case .none, .dead: return linkNote ?? PanelText.commandNotLinked
        case .foreign: return PanelText.skillForeign("~/" + SkillInstaller.linkPath)
        }
    }
}

/// What the button does and the paths it writes, in Settings and in the
/// setup window.
struct AgentSetupOffer: View {
    let model: AgentSetupModel
    @State private var showsChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = model.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = model.linkNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.changes.isEmpty {
                DisclosureGroup("Show what changes", isExpanded: $showsChanges) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent Caffeine writes these and nothing else. Remove takes them out again.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.changes.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
    }
}

/// The top of the "Command line" section of Settings > Agents: the
/// button, and after it the state per agent with "Remove".
struct AgentSetupRows: View {
    let model: AgentSetupModel
    let setUp: () -> Void
    let install: (SkillCatalogEntry) -> Void
    let link: () -> Void
    let remove: () -> Void

    var body: some View {
        if !model.available {
            Text(PanelText.agentSetupUnavailable)
                .font(.callout)
        } else if model.isSetUp {
            ForEach(model.snapshot.agents) { agent in
                row(
                    agent.entry.displayName, detail: AgentSetupModel.detail(agent.status), error: model.errors[agent.id],
                    action: AgentSetupModel.action(agent.status)
                ) { install(agent.entry) }
            }
            row(
                PanelText.commandLinkTitle, detail: model.linkDetail, error: model.errors[SkillInstaller.linkKey],
                action: model.canLink ? "Link" : nil, run: link
            )
            if let hint = model.pathHint {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hint)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    CopyLine(text: ShellPath.exportLine, title: "Copy line")
                }
            }
            HStack {
                Text(PanelText.agentSetupRemoveExplained)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove", action: remove)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button(PanelText.agentSetupButton, action: setUp)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.summary == nil)
                AgentSetupOffer(model: model)
                ForEach(model.snapshot.agents.filter { model.errors[$0.id] != nil }) { agent in
                    failure(model.errors[agent.id] ?? "")
                }
                if let error = model.errors[SkillInstaller.linkKey] { failure(error) }
            }
        }
        ForEach(model.otherErrors, id: \.self, content: failure)
    }

    private func failure(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ title: String, detail: String, error: String?, action: String?, run: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error { failure(error) }
            }
            Spacer(minLength: 8)
            if let action { Button(action, action: run) }
        }
    }
}

/// One line of text to copy, with its button.
struct CopyLine: View {
    let text: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(title) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
