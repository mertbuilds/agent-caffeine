import Foundation

/// Finds out whether a tool's phone or web access to this Mac is on. Only
/// what official documentation or a look at a real Mac proves is detected.
///
/// Claude Code Remote Control (code.claude.com/docs/en/remote-control):
/// it is on for a `claude remote-control` server, for a session started
/// with `--remote-control` or `--rc`, and for every interactive session
/// when `remoteControlAtStartup` is true in `~/.claude/settings.json`.
/// `disableRemoteControl` turns all of it off. Confidence is medium: the
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

    /// `sessions` holds the arguments of each Claude Code session process,
    /// without the command name.
    static func claudeRemoteControl(sessions: [[String]], settings: ClaudeSettings) -> Bool {
        guard !settings.disabled else { return false }
        return sessions.contains { arguments in
            if arguments.first == "remote-control" || arguments.contains("--remote-control") || arguments.contains("--rc") { return true }
            let interactive = !arguments.contains("-p") && !arguments.contains("--print")
            return settings.atStartup && interactive
        }
    }
}
