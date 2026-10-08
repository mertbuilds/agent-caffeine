import AppKit
import SwiftUI

/// The "Command line" section of Settings > Agents.
struct CommandLinePreferencesSection: View {
    let setup: CommandLineSetup

    var body: some View {
        Section("Command line") {
            Text(PanelText.commandLineExplained)
                .font(.callout)
                .foregroundStyle(.secondary)
            line(setup.toolPath, copy: "Copy path")
            VStack(alignment: .leading, spacing: 6) {
                Text(PanelText.commandLineInstallExplained)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                line(setup.installCommand, copy: "Copy install command")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(PanelText.commandLineMCPExplained)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                line(setup.mcpConfig, copy: "Copy MCP entry")
            }
        }
    }

    private func line(_ text: String, copy title: String) -> some View {
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
