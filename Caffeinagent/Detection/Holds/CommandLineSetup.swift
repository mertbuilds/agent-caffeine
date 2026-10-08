import Foundation

/// What Settings shows about the command line tool for a setup by hand:
/// where it is, the command that puts it on the PATH, and the entry for
/// an agent's MCP servers. The app only shows these, and the user runs
/// the command. "Set up for agents" is `SkillInstaller`.
struct CommandLineSetup: Equatable {
    static let toolName = "agent-caffeine"
    /// Next to the app's own binary and the hook command.
    static let pathInApp = "/Contents/MacOS/" + toolName

    /// The path of the tool in the copy of the app that runs.
    var toolPath: String

    init(appPath: String) {
        toolPath = appPath + Self.pathInApp
    }

    /// For `sh`: the path in single quotes, so the space in it is safe.
    var installCommand: String {
        "mkdir -p ~/.local/bin && ln -sf \(HookCatalog.shellQuoted(toolPath)) ~/.local/bin/\(Self.toolName)"
    }

    /// `{"command": "<path>", "args": ["mcp"]}`, with the path as JSON.
    var mcpConfig: String {
        "{\"command\": \(JSONSourceText.literal(toolPath)), \"args\": [\"mcp\"]}"
    }
}
