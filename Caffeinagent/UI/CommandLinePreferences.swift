import SwiftUI

/// The "Command line" section of Settings > Agents: "Set up for agents"
/// first, and below it the lines to copy for a setup by hand.
struct CommandLinePreferencesSection: View {
    let setup: CommandLineSetup
    var agentSetup = AgentSetupModel()
    var setUpForAgents: () -> Void = {}
    var installSkill: (SkillCatalogEntry) -> Void = { _ in }
    var linkTool: () -> Void = {}
    var removeAgentSetup: () -> Void = {}

    var body: some View {
        Section("Command line") {
            Text("\(PanelText.commandLineExplained) \(PanelText.agentSetupExplained)")
                .font(.callout)
                .foregroundStyle(.secondary)
            AgentSetupRows(model: agentSetup, setUp: setUpForAgents, install: installSkill, link: linkTool, remove: removeAgentSetup)
            Text(PanelText.agentSetupByHand)
                .font(.callout)
                .foregroundStyle(.secondary)
            CopyLine(text: setup.toolPath, title: "Copy path")
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
    }
}
