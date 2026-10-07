import Darwin
import Foundation

/// What the hook command does once it has its input: find the agent process
/// that ran it and write that process's state file. It never throws and
/// never prints, because a hook must not disturb the agent.
enum HookCommand {
    static let maxAncestors = 24
    /// Two readings of one start time can differ in the last digit.
    static let startTolerance: TimeInterval = 0.001

    static let inputLimit = 64 * 1024
    /// How long the hook waits for the first byte of its input. An agent
    /// under load can take longer than a moment to write it, and an event
    /// with no input has no session. The agents close the pipe when they
    /// have written, so this wait is paid only for an input that never comes.
    static let inputWait: TimeInterval = 1
    /// How long it waits for more once a part has come and the pipe is
    /// still open.
    static let inputQuiet: TimeInterval = 0.2
    /// The longest time the reading takes in all.
    static let inputTotal: TimeInterval = 2

    /// The hook's input: at most `limit` bytes are kept. What comes after
    /// the limit is read and dropped, so the agent never writes into a
    /// closed pipe. Reads to the end of the input, and gives up at the
    /// waits above, so a pipe that stays open never holds the agent.
    static func readInput(
        from descriptor: Int32 = STDIN_FILENO, limit: Int = inputLimit,
        wait: TimeInterval = inputWait, quiet: TimeInterval = inputQuiet, total: TimeInterval = inputTotal
    ) -> [UInt8] {
        func nanoseconds(_ seconds: TimeInterval) -> UInt64 { UInt64(max(seconds, 0) * 1_000_000_000) }
        var input: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let start = DispatchTime.now().uptimeNanoseconds
        let end = start + nanoseconds(total)
        var deadline = min(start + nanoseconds(wait), end)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            var polled = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&polled, 1, Int32((deadline - now) / 1_000_000) + 1) > 0 else { break }
            let count = read(descriptor, &chunk, chunk.count)
            guard count > 0 else { break }
            if input.count < limit { input.append(contentsOf: chunk[..<min(count, limit - input.count)]) }
            deadline = min(DispatchTime.now().uptimeNanoseconds + nanoseconds(quiet), end)
        }
        return input
    }

    /// The nearest process above the hook command that is the agent the hook
    /// was registered for. `chain` is nearest first. Nil when the hook ran
    /// under another tool, as when Droid or Cursor replay Claude Code's hooks.
    static func agentProcess(in chain: [ProcessInfoRow], hookAgent: String, catalog: AgentCatalog = .standard) -> ProcessInfoRow? {
        guard let ids = HookEvents.definitionIDs[hookAgent] else { return nil }
        // The nearest agent decides. A helper is passed over, so a hook
        // that a Cursor helper started lands on Cursor's main process, and
        // a hook of a CLI in the editor's terminal does not.
        for row in chain {
            guard let match = catalog.match(row, userNames: []), match.role != .helper else { continue }
            return ids.contains(match.definition.id) ? row : nil
        }
        return nil
    }

    /// The processes above `pid`, nearest first.
    static func ancestors(of pid: Int32) -> [ProcessInfoRow] {
        var chain: [ProcessInfoRow] = []
        var seen: Set<Int32> = [pid]
        var next = SystemProcessCensus.row(of: pid)?.ppid
        while let current = next, current > 1, seen.insert(current).inserted, chain.count < maxAncestors,
              let row = SystemProcessCensus.row(of: current) {
            chain.append(row)
            next = row.ppid
        }
        return chain
    }

    /// When this hook command started. The agent starts its hook commands
    /// in the order of its events, and a command can take longer than the
    /// next one to read its input. So this time, and not the time of the
    /// write, is the time of the event. Nil when the process table does
    /// not give it.
    static func startTime(of pid: Int32 = getpid()) -> Date? {
        SystemProcessCensus.row(of: pid).map { Date(timeIntervalSince1970: $0.startTime) }
    }

    /// False when nothing was recorded.
    @discardableResult
    static func record(agent: String, event: String, input: [UInt8], chain: [ProcessInfoRow], directory: URL, now: Date = Date()) -> Bool {
        let fields = HookInput.topLevelStrings(in: input)
        let action = HookEvents.action(
            agent: agent, event: event, notificationType: fields["notification_type"], isSubagent: fields["agent_id"] != nil
        )
        guard action != .ignore, let process = agentProcess(in: chain, hookAgent: agent) else { return false }
        let sessionID = HookInput.sessionKeys.lazy.compactMap { fields[$0] }.first { !$0.isEmpty }
        // An input that came and names no session, as one that is cut off
        // before the id: the state would land on a session with no name,
        // which no later event ends. With no input at all every event of
        // the process lands there, and that is one session.
        if sessionID == nil, !input.isEmpty, case .set = action { return false }
        let url = directory.appendingPathComponent(HookStateFile.fileName(agent: agent, pid: process.pid))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        let lock = Lock(path: directory.appendingPathComponent(".lock").path)
        defer { lock.release() }

        var file = HookStateFile(agent: agent, pid: process.pid, start: process.startTime)
        if let data = try? Data(contentsOf: url), let known = try? JSONDecoder().decode(HookStateFile.self, from: data),
           known.v == HookStateFile.currentVersion, abs(known.start - process.startTime) <= startTolerance {
            file = known
        }
        let stamp = HookEvents.stampedAgents.contains(agent) ? HookStamp(fields: fields) : nil
        file.apply(action, session: HookStateFile.sessionKey(sessionID), event: event, at: now, stamp: stamp)
        if file.sessions.isEmpty {
            unlink(url.path)
            return true
        }
        guard let data = try? JSONEncoder().encode(file) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Two hooks of one agent can run at the same moment. The lock makes
    /// read, change and write one step. It gives up after a short wait, so a
    /// stuck lock never holds a hook.
    private struct Lock {
        private let descriptor: Int32

        init(path: String) {
            descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { return }
            var tries = 0
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0, tries < 50 {
                usleep(2000)
                tries += 1
            }
        }

        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }
}
