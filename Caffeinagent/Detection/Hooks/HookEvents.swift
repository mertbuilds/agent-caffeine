import Foundation

/// What one hook event does to the state of its session.
enum HookAction: Equatable {
    case set(ReportedState)
    /// The session is over and its entry is removed.
    case end
    case ignore
}

/// Which hook events of each agent are registered and what they mean. The
/// hook command and the installer both read this table, so an event that is
/// not here is never registered and never recorded.
enum HookEvents {
    struct Rule: Equatable {
        let event: String
        /// For an event that carries a notification type, the action of a
        /// type that `byNotificationType` does not name.
        let action: HookAction
        var byNotificationType: [String: HookAction] = [:]
        /// The `matcher` of the registered entry, nil for none.
        var matcher: String?
    }

    /// The command and the state files are bound to this bundle id.
    static let bundleID = "com.caffeinagent.app"

    private static let waitingTypes: [String: HookAction] = [
        "permission_prompt": .set(.waitingForUser),
        "elicitation_dialog": .set(.waitingForUser),
        "elicitation_url_dialog": .set(.waitingForUser),
        // Sent a minute after the agent stopped, and by Droid after a cancel.
        "idle_prompt": .set(.idle),
    ]

    /// By hook agent id. The order is the order of the entries in the config.
    static let rules: [String: [Rule]] = [
        "claude": [
            Rule(event: "UserPromptSubmit", action: .set(.working)),
            Rule(event: "PreToolUse", action: .set(.working)),
            Rule(event: "PostToolUse", action: .set(.working)),
            Rule(event: "Notification", action: .ignore, byNotificationType: waitingTypes,
                 matcher: "permission_prompt|elicitation_dialog|elicitation_url_dialog|idle_prompt"),
            Rule(event: "Stop", action: .set(.idle)),
            Rule(event: "SessionEnd", action: .end),
        ],
        "codex": [
            Rule(event: "UserPromptSubmit", action: .set(.working)),
            // In Codex's `HookEventName` (docs/research/03-codex-remote.md).
            Rule(event: "PreToolUse", action: .set(.working)),
            Rule(event: "PermissionRequest", action: .set(.waitingForUser)),
            Rule(event: "PostToolUse", action: .set(.working)),
            Rule(event: "Stop", action: .set(.idle)),
            Rule(event: "Interrupt", action: .set(.idle)),
            Rule(event: "SessionEnd", action: .end),
        ],
        "droid": [
            Rule(event: "UserPromptSubmit", action: .set(.working)),
            Rule(event: "PreToolUse", action: .set(.working)),
            Rule(event: "PostToolUse", action: .set(.working)),
            Rule(event: "Notification", action: .ignore, byNotificationType: waitingTypes),
            Rule(event: "Stop", action: .set(.idle)),
            Rule(event: "SessionEnd", action: .end),
        ],
        // The plugin turns opencode's bus events into these names.
        "opencode": [
            Rule(event: "session.busy", action: .set(.working)),
            Rule(event: "permission.asked", action: .set(.waitingForUser)),
            Rule(event: "permission.replied", action: .set(.working)),
            Rule(event: "session.idle", action: .set(.idle)),
            Rule(event: "session.deleted", action: .end),
        ],
        // The names of Pi's own extension events. The extension sends
        // `ui_prompt_*` only during a run, and the end of a compaction only
        // outside one.
        "pi": [
            Rule(event: "session_start", action: .set(.idle)),
            Rule(event: "agent_start", action: .set(.working)),
            Rule(event: "turn_start", action: .set(.working)),
            Rule(event: "tool_execution_start", action: .set(.working)),
            Rule(event: "tool_execution_end", action: .set(.working)),
            Rule(event: "ui_prompt_start", action: .set(.waitingForUser)),
            Rule(event: "ui_prompt_end", action: .set(.working)),
            Rule(event: "session_before_compact", action: .set(.working)),
            Rule(event: "session_compact", action: .set(.idle)),
            Rule(event: "session_compact_failed", action: .set(.idle)),
            // After every run, also one that was stopped or that failed.
            // `agent_end` is not the end: a retry or queued work can follow.
            Rule(event: "agent_settled", action: .set(.idle)),
            Rule(event: "session_shutdown", action: .end),
        ],
        // Only events whose answer Cursor does not read
        // (docs/research/08-cursor.md). `preToolUse`, `beforeShellExecution`,
        // `beforeMCPExecution`, `beforeReadFile` and `subagentStart` ask for
        // a permission, and an answer Cursor cannot read blocks the action:
        // they are never registered. No event exists for an approval wait.
        "cursor": [
            Rule(event: "beforeSubmitPrompt", action: .set(.working)),
            Rule(event: "afterAgentThought", action: .set(.working)),
            Rule(event: "afterAgentResponse", action: .set(.working)),
            Rule(event: "postToolUse", action: .set(.working)),
            Rule(event: "postToolUseFailure", action: .set(.working)),
            Rule(event: "afterShellExecution", action: .set(.working)),
            Rule(event: "afterFileEdit", action: .set(.working)),
            Rule(event: "afterMCPExecution", action: .set(.working)),
            Rule(event: "stop", action: .set(.idle)),
            Rule(event: "sessionEnd", action: .end),
        ],
        // Grok Build's own names (docs/research/10-grok-build.md). An
        // empty answer changes nothing for each of them: `Stop` lets
        // the turn end on it. `PreToolUse` can deny a tool and is never
        // registered. An interrupt sends no event: the event log of the
        // session says that the turn ended (`GrokEventsReader`).
        "grok": [
            Rule(event: "UserPromptSubmit", action: .set(.working)),
            Rule(event: "PostToolUse", action: .set(.working)),
            Rule(event: "PostToolUseFailure", action: .set(.working)),
            Rule(event: "Stop", action: .set(.idle)),
            Rule(event: "StopFailure", action: .set(.idle)),
            Rule(event: "SessionEnd", action: .end),
        ],
    ]

    /// The agents whose hook input holds a `HookStamp`. The `ts` or `seq`
    /// of another agent's input means something else and is not read.
    static let stampedAgents: Set<String> = ["opencode", "pi"]

    /// The `AgentDefinition.id`s a hook agent id covers. The Codex app runs
    /// the same hooks file as the Codex CLI, and the Claude app starts its
    /// Claude Code with `--setting-sources=user,project,local`.
    static let definitionIDs: [String: Set<String>] = [
        "claude": ["claude", AgentCatalog.claudeDesktopID],
        "codex": ["codex", "codex-desktop"],
        "droid": ["droid"],
        "opencode": ["opencode"],
        "pi": ["pi"],
        "cursor": [AgentCatalog.cursorDesktopID],
        "grok": [AgentCatalog.grokID],
    ]

    static func hookAgent(forDefinition id: String) -> String? {
        definitionIDs.first { $0.value.contains(id) }?.key
    }

    /// A subagent that stops does not end the turn of its session, so its
    /// idle and end events are dropped.
    static func action(agent: String, event: String, notificationType: String?, isSubagent: Bool) -> HookAction {
        guard let rule = rules[agent]?.first(where: { $0.event == event }) else { return .ignore }
        let action = notificationType.flatMap { rule.byNotificationType[$0] } ?? rule.action
        if isSubagent, action == .set(.idle) || action == .end { return .ignore }
        return action
    }
}
