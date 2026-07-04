import Foundation
import os

@MainActor
final class ProcessWatcher: ObservableObject {
    @Published private(set) var agents: [DetectedAgent] = []
    @Published var allowlist: [String] {
        didSet {
            UserDefaults.standard.set(allowlist, forKey: Self.allowlistKey)
            scan()
        }
    }

    private let pollTimer: DispatchSourceTimer
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "ProcessWatcher")
    private static let allowlistKey = "ProcessWatcher.allowlist"
    // Curated from skills.sh supported-agents list (51 entries). Skipped: bob,
    // continue, cortex, cursor (IDE), droid, github-copilot, kimi-cli, kode,
    // mux, pi, replit, roo, universal, warp, adal — too-generic names that
    // collide with non-agent processes the user is likely running.
    static let defaultAllowlist = [
        "aider", "aider-desk",
        "amp",
        "antigravity",
        "augment",
        "claude",
        "cline",
        "codearts-agent",
        "codebuddy",
        "codemaker",
        "codestudio",
        "codex",
        "command-code",
        "crush",
        "cursor-agent",
        "deepagents",
        "devin",
        "dexto",
        "firebender",
        "forgecode",
        "gemini", "gemini-cli",
        "goose",
        "hermes-agent",
        "iflow-cli",
        "junie",
        "kilo",
        "kiro-cli",
        "mcpjam",
        "mistral-vibe",
        "neovate",
        "opencode",
        "openclaw",
        "openhands",
        "pochi",
        "qoder",
        "qwen-code",
        "rovodev",
        "tabnine-cli",
        "trae", "trae-cn",
        "windsurf",
        "zencoder",
    ]

    init() {
        let stored = UserDefaults.standard.array(forKey: Self.allowlistKey) as? [String]
        if let stored {
            let missing = Self.defaultAllowlist.filter { !stored.contains($0) }
            self.allowlist = stored + missing
        } else {
            self.allowlist = Self.defaultAllowlist
        }
        self.pollTimer = DispatchSource.makeTimerSource(queue: .main)
        pollTimer.schedule(deadline: .now() + 1, repeating: 5.0)
        pollTimer.setEventHandler { [weak self] in self?.scan() }
        pollTimer.resume()
        scan()
    }

    func scan() {
        let names = runningProcessNames()
        let allowed = Set(allowlist.map { $0.lowercased() })
        let matches = names.filter { allowed.contains($0.lowercased()) }
        let now = Date()
        agents = matches.sorted().map {
            DetectedAgent(id: "proc:\($0)", source: .process, label: $0, state: .active, lastActivity: now)
        }
    }

    private func runningProcessNames() -> Set<String> {
        // sysctl's p_comm is the executed binary's basename, which for
        // version-managed CLIs isn't the command users run — Claude Code's
        // binary is named after its version (e.g. "2.1.199"), so it never
        // matches the allowlist. ps resolves the accounting names users
        // expect and behaves identically on macOS 13 through 26.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axco", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            log.error("ps spawn failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            log.error("ps exited \(task.terminationStatus)")
            return []
        }
        var names = Set<String>()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }
}
