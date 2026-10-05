import Foundation

/// Finds out whether a tool's phone or web access to this Mac is on. Only
/// what official documentation or a look at a real Mac proves is detected.
///
/// Claude Code Remote Control (code.claude.com/docs/en/remote-control):
/// it is on for a `claude remote-control` server, for a session started
/// with `--remote-control` or `--rc`, and for every interactive session
/// when `remoteControlAtStartup` is true in `~/.claude/settings.json`.
/// `disableRemoteControl` turns all of it off. A session counts only when
/// a person sits at it: it has a terminal, and it is no headless run
/// (`-p`, `--print`), no SDK session (`--input-format`) and no
/// `claude mcp` command. Without that, the SDK sessions of other apps and
/// `claude mcp serve` kept a plugged-in Mac awake. Confidence is medium: the
/// rules are from the documentation, and the on state was never seen on the
/// test Mac. A session that turns it on later with `/remote-control` is not
/// seen: no file or argument is known to change.
///
/// Codex has no detector. Its `exec-server --remote` process runs on the
/// test Mac while phone access is not set up, so it proves nothing, and
/// where the app keeps "Control this Mac" is not known.
enum RemoteAccessDetector {
    /// The tools a detector exists for. Preferences shows the switch only
    /// when this is not empty.
    static let detectedTools = ["Claude Code"]

    struct ClaudeSettings: Equatable {
        var atStartup = false
        var disabled = false

        /// Only the two switches are taken from the file.
        init(json data: Data) {
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            atStartup = root["remoteControlAtStartup"] as? Bool ?? false
            disabled = root["disableRemoteControl"] as? Bool ?? false
        }

        init(atStartup: Bool = false, disabled: Bool = false) {
            self.atStartup = atStartup
            self.disabled = disabled
        }
    }

    /// One Claude Code session process.
    struct ClaudeSession: Equatable {
        /// Without the command name.
        var arguments: [String]
        /// The process has a controlling terminal.
        var hasTerminal: Bool

        var isInteractive: Bool {
            hasTerminal && arguments.first != "mcp"
                && !arguments.contains { $0 == "-p" || $0 == "--print" || $0.hasPrefix("--input-format") }
        }
    }

    /// The server mode is no session of a person and needs no terminal.
    static func claudeRemoteControl(sessions: [ClaudeSession], settings: ClaudeSettings) -> Bool {
        guard !settings.disabled else { return false }
        return sessions.contains { session in
            if session.arguments.first == "remote-control" { return true }
            guard session.isInteractive else { return false }
            return settings.atStartup || session.arguments.contains("--remote-control") || session.arguments.contains("--rc")
        }
    }
}
