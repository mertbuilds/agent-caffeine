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
    private let scanQueue = DispatchQueue(label: "com.caffeinagent.app.ProcessWatcher", qos: .utility)
    private var scanInFlight = false
    private var rescanPending = false
    private var previous: Snapshot?
    private var lastWork: [Int32: WorkMark] = [:]
    // Measured 2026-10-05 over 5 second windows on 9 Claude Code sessions.
    // Idle at the prompt (7 sessions, 700 windows): median 0.04, p95 0.08,
    // max 0.38 CPU seconds; only 3 windows, one burst, reached 0.15. Working
    // while waiting on the model (100 windows): min 0.08, median 0.24, max
    // 0.46; 85 of 100 windows reached 0.15 and the longest quieter stretch
    // was 25 seconds. Tools, builds and tests use far more. So 0.15 CPU
    // seconds per 5 seconds (3% of one core) counts as work, and the grace
    // period bridges quiet stretches about five times that long while an
    // idle agent still lets the Mac sleep two minutes after its last work.
    nonisolated static let workCPUFraction = 0.03
    nonisolated static let workGracePeriod: TimeInterval = 120
    nonisolated private static let log = Logger(subsystem: "com.caffeinagent.app", category: "ProcessWatcher")
    nonisolated private static let allowlistKey = "ProcessWatcher.allowlist"
    nonisolated private static let knownDefaultsKey = "ProcessWatcher.knownDefaults"
    // Curated from skills.sh supported-agents list (51 entries). Skipped: bob,
    // continue, cortex, cursor (IDE), kimi-cli, kode, mux, replit, roo,
    // universal, warp, adal. These are too-generic names that collide with
    // non-agent processes the user is likely running.
    nonisolated static let defaultAllowlist = [
        "aider", "aider-desk",
        "amp",
        "antigravity",
        "augment",
        "claude",
        "cline",
        "cn",
        "codearts-agent",
        "codebuddy",
        "codemaker",
        "codestudio",
        "codex",
        "command-code",
        "copilot",
        "crush",
        "cursor-agent",
        "deepagents",
        "devin",
        "dexto",
        "droid",
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
        "pi",
        "pochi",
        "qoder",
        "qwen-code",
        "rovodev",
        "tabnine-cli",
        "trae", "trae-cn",
        "windsurf",
        "zencoder",
    ]
    // Shipped in the same release that started saving known defaults. Older
    // builds have never seen them, so they still reach existing users once.
    nonisolated private static let addedWithKnownDefaults = ["cn", "copilot", "droid", "pi"]

    init() {
        self.allowlist = Self.loadAllowlist(from: .standard)
        self.pollTimer = DispatchSource.makeTimerSource(queue: .main)
        pollTimer.schedule(deadline: .now() + 1, repeating: 5.0)
        pollTimer.setEventHandler { [weak self] in
            // Skip the tick while the previous scan is still running.
            guard let self, !self.scanInFlight else { return }
            self.scan()
        }
        pollTimer.resume()
        scan()
    }

    /// Reads the saved allowlist and merges in defaults added since the last
    /// launch. Only those are merged in, so a removed default stays removed.
    nonisolated static func loadAllowlist(from defaults: UserDefaults) -> [String] {
        let allowlist: [String]
        if let stored = defaults.array(forKey: allowlistKey) as? [String] {
            let known = defaults.array(forKey: knownDefaultsKey) as? [String]
                ?? defaultAllowlist.filter { !addedWithKnownDefaults.contains($0) }
            let new = defaultAllowlist.filter { !known.contains($0) && !stored.contains($0) }
            allowlist = stored + new
            // didSet does not run in init, and the next launch treats these as known.
            if !new.isEmpty { defaults.set(allowlist, forKey: allowlistKey) }
        } else {
            allowlist = defaultAllowlist
        }
        defaults.set(defaultAllowlist, forKey: knownDefaultsKey)
        return allowlist
    }

    /// Runs ps off the main thread. A call while a scan is running (an
    /// allowlist edit) scans again once it returns, so the new list applies.
    func scan() {
        guard !scanInFlight else {
            rescanPending = true
            return
        }
        scanInFlight = true
        let previous = previous, lastWork = lastWork, allowlist = allowlist
        scanQueue.async {
            let result = Self.runningProcesses().map { output in
                let snapshot = Snapshot(rows: Self.parseProcessList(output), time: Self.monotonicNow(), date: Date())
                return (snapshot, Self.evaluate(current: snapshot, previous: previous, lastWork: lastWork, allowlist: allowlist))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanInFlight = false
                if let (snapshot, evaluated) = result {
                    self.previous = snapshot
                    self.lastWork = evaluated.lastWork
                    if self.agents != evaluated.agents { self.agents = evaluated.agents }
                } else {
                    self.previous = nil
                    self.lastWork = [:]
                    if !self.agents.isEmpty { self.agents = [] }
                }
                if self.rescanPending {
                    self.rescanPending = false
                    self.scan()
                }
            }
        }
    }

    // CLOCK_MONOTONIC keeps counting while the Mac sleeps (unlike
    // CLOCK_UPTIME_RAW), so a long sleep ends the grace period and dilutes
    // the CPU rate, and setting the wall clock changes neither.
    nonisolated static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    nonisolated private static func runningProcesses() -> String? {
        // sysctl's p_comm is the executed binary's basename, which for
        // version-managed CLIs isn't the command users run. Claude Code's
        // binary is named after its version (e.g. "2.1.199"), so it never
        // matches the allowlist. ps resolves the accounting names users
        // expect and behaves identically on macOS 13 through 26. args adds
        // the path and arguments needed to skip app-bundled helpers; pid,
        // ppid and time give the process tree and its CPU use.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axww", "-o", "pid=,ppid=,time=,ucomm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            Self.log.error("ps spawn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            Self.log.error("ps exited \(task.terminationStatus)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    struct ProcessRow: Equatable {
        let pid: Int32
        let ppid: Int32
        let cpuSeconds: Double
        let comm: String
        let args: String
    }

    /// `time` is `monotonicNow()` and drives all arithmetic; `date` is only
    /// shown as the last activity.
    struct Snapshot {
        let rows: [ProcessRow]
        let time: TimeInterval
        let date: Date
    }

    struct WorkMark: Equatable {
        let time: TimeInterval
        let date: Date
    }

    /// Parses `ps -o pid=,ppid=,time=,ucomm=,args=` lines. The first three
    /// columns are separated by spaces. ucomm follows after one space and is
    /// padded to 16 bytes, so the args start 17 bytes later even when either
    /// part contains spaces.
    nonisolated static func parseProcessList(_ psOutput: String) -> [ProcessRow] {
        psOutput.split(separator: "\n").compactMap { line in
            let bytes = Array(line.utf8)
            var index = 0
            func nextField() -> String? {
                while index < bytes.count && bytes[index] == 0x20 { index += 1 }
                let start = index
                while index < bytes.count && bytes[index] != 0x20 { index += 1 }
                return index > start ? String(decoding: bytes[start..<index], as: UTF8.self) : nil
            }
            guard let pid = nextField().flatMap({ Int32($0) }),
                  let ppid = nextField().flatMap({ Int32($0) }),
                  let cpu = nextField().flatMap(parseCPUTime) else { return nil }
            let rest = bytes.dropFirst(index + 1)
            let comm = String(decoding: rest.prefix(16), as: UTF8.self).trimmingCharacters(in: .whitespaces)
            let args = String(decoding: rest.dropFirst(17), as: UTF8.self)
            return ProcessRow(pid: pid, ppid: ppid, cpuSeconds: cpu, comm: comm, args: args)
        }
    }

    /// Parses ps `time`, `[days-][hours:]minutes:seconds`. macOS prints
    /// minutes past 59 (for example `842:39.83`), other systems roll them
    /// into hours, so every colon part is folded in base 60.
    nonisolated static func parseCPUTime(_ text: String) -> Double? {
        var days = 0.0
        var clock = Substring(text)
        if let dash = clock.firstIndex(of: "-") {
            guard let d = Double(clock[..<dash]) else { return nil }
            days = d
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            seconds = seconds * 60 + value
        }
        return days * 86400 + seconds
    }

    /// A process matches by its accounting name or the basename of argv[0]
    /// (set by CLIs that rename their process title).
    nonisolated static func agentName(of row: ProcessRow, allowed: Set<String>) -> String? {
        let argv0 = row.args.split(separator: " ").first.map(String.init) ?? ""
        let argv0Name = (argv0 as NSString).lastPathComponent
        guard let name = [row.comm, argv0Name].first(where: { allowed.contains($0.lowercased()) }) else { return nil }
        if isAppBundled(row.args) { return nil }
        // ChatGPT and IDE extensions keep `codex app-server` running for days.
        if name.lowercased() == "codex" && row.args.split(separator: " ").contains(where: { $0 == "app-server" || $0 == "exec-server" }) {
            return nil
        }
        return name
    }

    /// CPU seconds the process and its descendants used since the previous
    /// snapshot. A pid counts as the same process only when its name matches
    /// and its CPU time did not go down, so a reused pid and a child that
    /// started since then count with their full CPU time. Children that exited
    /// in between drop out instead of making the sum negative.
    nonisolated static func subtreeCPUDelta(of current: ProcessRow, children: [Int32: [ProcessRow]], previous: [Int32: ProcessRow]) -> Double {
        var total = 0.0
        var visited: Set<Int32> = []
        var stack = [current]
        while let row = stack.popLast() {
            guard visited.insert(row.pid).inserted else { continue }
            if let old = previous[row.pid], old.comm == row.comm, row.cpuSeconds >= old.cpuSeconds {
                total += row.cpuSeconds - old.cpuSeconds
            } else {
                total += row.cpuSeconds
            }
            stack += children[row.pid] ?? []
        }
        return total
    }

    /// Decides working or idle for each matched process and merges processes
    /// with the same name into one entry. A process is active while its
    /// subtree used at least `workCPUFraction` of one core since the previous
    /// snapshot, and for `workGracePeriod` after that. A process seen for the
    /// first time counts as working, because the user just started it.
    /// `lastWork` maps each matched pid to the end of its last working scan.
    /// A window shorter than a second (a rescan after an allowlist edit) is
    /// too short to measure, so it never counts as work.
    nonisolated static func evaluate(current: Snapshot, previous: Snapshot?, lastWork: [Int32: WorkMark], allowlist: [String]) -> (agents: [DetectedAgent], lastWork: [Int32: WorkMark]) {
        let allowed = Set(allowlist.map { $0.lowercased() })
        let now = WorkMark(time: current.time, date: current.date)
        let previousRows = Dictionary((previous?.rows ?? []).map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: current.rows.filter { $0.pid != $0.ppid }, by: \.ppid)
        let elapsed = previous.map { current.time - $0.time } ?? 0
        var nextLastWork: [Int32: WorkMark] = [:]
        var byName: [String: (state: AgentState, lastActivity: Date)] = [:]
        for row in current.rows {
            guard let name = agentName(of: row, allowed: allowed) else { continue }
            let old = previousRows[row.pid]
            let sameProcess = old.map { $0.comm == row.comm && row.cpuSeconds >= $0.cpuSeconds } ?? false
            var worked = now
            if sameProcess, let known = lastWork[row.pid] {
                let delta = subtreeCPUDelta(of: row, children: children, previous: previousRows)
                worked = elapsed >= 1 && delta / elapsed >= workCPUFraction ? now : known
            }
            nextLastWork[row.pid] = worked
            let state: AgentState = current.time - worked.time < workGracePeriod ? .active : .waitingForInput
            let merged = byName[name]
            byName[name] = (max(merged?.state ?? state, state), max(merged?.lastActivity ?? worked.date, worked.date))
        }
        let agents = byName.sorted { $0.key < $1.key }.map { name, entry in
            DetectedAgent(id: "proc:\(name)", source: .process, label: name, state: entry.state, lastActivity: entry.lastActivity)
        }
        return (agents, nextLastWork)
    }

    /// True when argv[0] is a path inside an .app bundle. The bundle path may
    /// contain spaces, but a space followed by "-" or "/" starts a new argument.
    nonisolated private static func isAppBundled(_ args: String) -> Bool {
        guard args.hasPrefix("/"), let range = args.range(of: ".app/Contents/") else { return false }
        let head = args[..<range.lowerBound]
        return !head.contains(" -") && !head.contains(" /")
    }
}
