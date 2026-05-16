import Foundation
import Darwin
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
        var size: Int = 0
        if sysctlbyname("kern.proc.all", nil, &size, nil, 0) != 0 { return [] }
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 16
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var newSize = capacity * MemoryLayout<kinfo_proc>.stride
        let result = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            sysctlbyname("kern.proc.all", ptr.baseAddress, &newSize, nil, 0)
        }
        if result != 0 { return [] }
        let count = newSize / MemoryLayout<kinfo_proc>.stride
        var names = Set<String>()
        for i in 0..<count {
            var proc = buffer[i]
            let name = withUnsafePointer(to: &proc.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }
}
