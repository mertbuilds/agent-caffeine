import Foundation

/// How one agent takes hooks: where its config is, what form it has, and
/// what the hooks tell that the passive detection cannot see.
struct HookCatalogEntry: Equatable, Identifiable {
    enum Format: Equatable {
        /// A JSON file with `<key path>.<Event>: [{matcher?, hooks: [{type, command, timeout}]}]`,
        /// the form of Claude Code, Codex and Droid.
        case jsonHookGroups(keyPath: [String])
        /// A JavaScript plugin file that is all ours.
        case pluginFile
    }

    /// The hook agent id, the first argument of the hook command.
    let id: String
    let displayName: String
    /// Relative to the home folder.
    let configPath: String
    let format: Format
    /// The states the hooks add to what agent caffeine sees without them.
    let adds: [ReportedState]
    /// One line for Preferences: what turning it on gives.
    let benefit: String
    /// What the user has to do in the agent after turning it on.
    let afterInstall: String?
    /// What the config path, the format and the event names were checked against.
    let confirmedBy: String

    var rules: [HookEvents.Rule] { HookEvents.rules[id] ?? [] }
    var definitionIDs: Set<String> { HookEvents.definitionIDs[id] ?? [] }
    var events: [String] { rules.map(\.event) }
}

enum HookCatalog {
    /// Raised when the command or the set of events changes, so entries of
    /// an older build read as outdated.
    static let version = 1
    /// Every entry we write holds this, and nothing else in a config does.
    static let marker = "/Contents/MacOS/CaffeinagentHook"
    /// The hook command points here and nowhere else, so it stays valid
    /// when the app updates and when a copy runs from another folder.
    static let stableAppPath = "/Applications/agent caffeine.app"
    static let timeoutSeconds = 5
    static let pluginFileName = "agent-caffeine.js"

    static let entries: [HookCatalogEntry] = [
        HookCatalogEntry(
            id: "claude", displayName: "Claude Code", configPath: ".claude/settings.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.waitingForUser],
            benefit: "Lets agent caffeine see when Claude Code waits for your permission",
            afterInstall: nil,
            confirmedBy: "code.claude.com/docs/en/hooks, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "codex", displayName: "Codex", configPath: ".codex/hooks.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.waitingForUser],
            benefit: "Lets agent caffeine see when Codex waits for your permission",
            afterInstall: "Codex runs a new hook only after you trust it. Run /hooks in Codex one time.",
            confirmedBy: "learn.chatgpt.com/docs/hooks, the Codex 0.159 binary, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "droid", displayName: "Droid", configPath: ".factory/settings.json",
            format: .jsonHookGroups(keyPath: ["hooks"]),
            adds: [.working, .waitingForUser, .idle],
            benefit: "Lets agent caffeine see when Droid works, waits for you or is done",
            afterInstall: nil,
            confirmedBy: "docs.factory.com/cli/configuration/hooks-guide, and the file on the test Mac"
        ),
        HookCatalogEntry(
            id: "opencode", displayName: "opencode", configPath: ".config/opencode/plugins/\(pluginFileName)",
            format: .pluginFile,
            adds: [.working, .waitingForUser, .idle],
            benefit: "Lets agent caffeine see when opencode works, waits for you or is done",
            afterInstall: "opencode loads the plugin the next time it starts.",
            confirmedBy: "opencode.ai/docs/plugins for the folder, the plugin form and the event names. The event payload is from the opencode source. Not run live."
        ),
    ]

    /// Known hook systems that are left out, and why.
    static let notConfirmed: [(agent: String, reason: String)] = [
        ("Cursor CLI", "It is not known which hooks.json events fire in cursor-agent, or what an empty answer does to beforeSubmitPrompt."),
        ("Gemini CLI", "The settings.json hook format is known from source only, and no Gemini config exists on the test Mac."),
        ("Grok, Pi, Amp, Antigravity, Copilot", "Known from another project's catalogue only."),
    ]

    static func entry(id: String) -> HookCatalogEntry? {
        entries.first { $0.id == id }
    }

    static func entry(forDefinition id: String) -> HookCatalogEntry? {
        entries.first { $0.definitionIDs.contains(id) }
    }

    static func executablePath(appPath: String = stableAppPath) -> String {
        appPath + marker
    }

    /// For `sh`: the path in single quotes, so a space in it is safe.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command of one event. It does nothing when the app is gone, and
    /// it never fails: a hook that fails shows an error in the agent.
    static func command(agent: String, event: String, appPath: String = stableAppPath) -> String {
        let executable = shellQuoted(executablePath(appPath: appPath))
        return "[ -x \(executable) ] && \(executable) \(agent) \(event) v=\(version) || true"
    }

    static func version(ofCommand command: String) -> Int? {
        guard let range = command.range(of: #" v=(\d+)"#, options: .regularExpression) else { return nil }
        return Int(command[range].dropFirst(3))
    }

    /// The opencode plugin. It hands each event to the hook command with
    /// the session id and nothing else.
    static func pluginSource(appPath: String = stableAppPath) -> String {
        """
        // \(pluginMarker) v=\(version)
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when opencode works, waits for you or is done.
        const hook = \(JSONSourceText.literal(executablePath(appPath: appPath)));

        const named = (event) => {
          const properties = event?.properties ?? {};
          switch (event?.type) {
            case "session.status": {
              const status = typeof properties.status === "string" ? properties.status : properties.status?.type;
              if (status === "busy" || status === "retry") return "session.busy";
              return status === "idle" ? "session.idle" : null;
            }
            case "session.idle":
            case "session.deleted":
            case "permission.asked":
            case "permission.replied":
              return event.type;
            default:
              return null;
          }
        };

        export const AgentCaffeine = async ({ $ }) => ({
          event: async ({ event }) => {
            try {
              const name = named(event);
              if (!name) return;
              const properties = event?.properties ?? {};
              const session = properties.sessionID ?? properties.info?.id ?? "";
              const input = new Response(JSON.stringify({ session_id: String(session) }));
              await $`${hook} opencode ${name} v=\(version) < ${input}`.quiet().nothrow();
            } catch {}
          },
        });

        """
    }

    static let pluginMarker = "agent-caffeine-hook"
}
