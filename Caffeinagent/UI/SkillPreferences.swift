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

    private func isForeign(_ status: SkillAgentStatus) -> Bool {
        if case .foreign = status { return true }
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

    /// The agents that have our skill, of this build or of an older one.
    var installed: [SkillCatalogEntry] {
        snapshot.agents.filter { agent in
            if case .installed = agent.status { return true }
            return isOutdated(agent.status)
        }.map(\.entry)
    }

    /// The one line Settings shows after the setup.
    var doneSummary: String? {
        PanelText.agentSetupDone(agents: installed.map(\.displayName), linked: isLinked)
    }

    /// After the setup something is left to do or went wrong: an agent
    /// with no skill or an old one, a link to make, a copy of the app
    /// that may not make it, or an error. "Details" is open then.
    var needsAttention: Bool {
        !errors.isEmpty || (isSetUp && (!pending.isEmpty || canLink || linkNote != nil))
    }

    /// The setup window offers the step while an agent has no skill.
    var isOffered: Bool { available && !pending.isEmpty }

    var summary: String? {
        PanelText.agentSetupSummary(
            agents: pending.map(\.displayName), links: canLink, found: !snapshot.agents.isEmpty,
            foreign: snapshot.agents.contains { isForeign($0.status) }
        )
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
    /// What a skill is, where the page does not say it already.
    var explains = false
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
                        if explains {
                            Text(PanelText.agentSetupExplained)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

/// The first section of Settings > Agents. Before the setup: the title,
/// what the button does, and the button. After it: one line, and
/// "Details" with the state per agent, the link and "Remove". The lines
/// for a setup by hand are closed below both.
struct AgentSetupSection: View {
    let model: AgentSetupModel
    let commandLine: CommandLineSetup
    var setUp: () -> Void = {}
    var install: (SkillCatalogEntry) -> Void = { _ in }
    var link: () -> Void = {}
    var remove: () -> Void = {}
    /// Nil until the user opens or closes "Details": it then follows
    /// `needsAttention`.
    @State private var showsDetails: Bool?

    var body: some View {
        Section {
            if !model.available {
                Text(PanelText.agentSetupUnavailable)
                    .font(.callout)
            } else if model.isSetUp {
                done
                DisclosureGroup(isExpanded: details) {
                    rows
                } label: {
                    Text(PanelText.agentSetupDetails)
                        .font(.callout)
                }
                if let hint = model.pathHint {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hint)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        CopyLine(text: ShellPath.exportLine, title: "Copy line")
                    }
                }
            } else {
                offer
            }
            ForEach(model.otherErrors, id: \.self, content: failure)
            CommandLineByHand(setup: commandLine)
        }
        // What is new to do is shown again, also after the user closed it.
        .onChange(of: model.needsAttention) { _ in showsDetails = nil }
    }

    private var details: Binding<Bool> {
        Binding(get: { showsDetails ?? model.needsAttention }, set: { showsDetails = $0 })
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(PanelText.agentSetupTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(PanelText.agentSetupButton, action: setUp)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.summary == nil)
            }
            AgentSetupOffer(model: model, explains: true)
            ForEach(model.snapshot.agents.filter { model.errors[$0.id] != nil }) { agent in
                failure(model.errors[agent.id] ?? "")
            }
            if let error = model.errors[SkillInstaller.linkKey] { failure(error) }
        }
    }

    @ViewBuilder
    private var done: some View {
        if let summary = model.doneSummary {
            if model.needsAttention {
                Text(summary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label {
                    Text(summary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowsContent
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var rowsContent: some View {
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
        HStack {
            Text(PanelText.agentSetupRemoveExplained)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove", action: remove)
        }
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

/// "Set up by hand" at the end of the first section of Settings >
/// Agents: the path of the tool, the command that links it, and the MCP
/// entry. Closed until the user opens it.
struct CommandLineByHand: View {
    let setup: CommandLineSetup
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(PanelText.commandLineExplained)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CopyLine(text: setup.toolPath, title: "Copy path")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(PanelText.commandLineInstallExplained)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CopyLine(text: setup.installCommand, title: "Copy install command")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(PanelText.commandLineMCPExplained)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    CopyLine(text: setup.mcpConfig, title: "Copy MCP entry")
                }
            }
            .padding(.top, 8)
        } label: {
            Text(PanelText.agentSetupByHand)
                .font(.callout)
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
