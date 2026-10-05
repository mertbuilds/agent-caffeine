import Darwin
import Foundation

/// What the hook command does once it has its input: find the agent process
/// that ran it and write that process's state file. It never throws and
/// never prints, because a hook must not disturb the agent.
enum HookCommand {
    static let maxAncestors = 24
    /// Two readings of one start time can differ in the last digit.
    static let startTolerance: TimeInterval = 0.001

    /// The nearest process above the hook command that is the agent the hook
    /// was registered for. `chain` is nearest first. Nil when the hook ran
    /// under another tool, as when Droid or Cursor replay Claude Code's hooks.
    static func agentProcess(in chain: [ProcessInfoRow], hookAgent: String, catalog: AgentCatalog = .standard) -> ProcessInfoRow? {
        guard let ids = HookEvents.definitionIDs[hookAgent] else { return nil }
        return chain.first { row in
            guard let match = catalog.match(row, userNames: []) else { return false }
            return match.role != .helper && ids.contains(match.definition.id)
        }
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

    /// False when nothing was recorded.
    @discardableResult
    static func record(agent: String, event: String, input: [UInt8], chain: [ProcessInfoRow], directory: URL, now: Date = Date()) -> Bool {
        let fields = HookInput.topLevelStrings(in: input)
        let action = HookEvents.action(
            agent: agent, event: event, notificationType: fields["notification_type"], isSubagent: fields["agent_id"] != nil
        )
        guard action != .ignore, let process = agentProcess(in: chain, hookAgent: agent) else { return false }
        let sessionID = HookInput.sessionKeys.lazy.compactMap { fields[$0] }.first
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
        file.apply(action, session: HookStateFile.sessionKey(sessionID), event: event, at: now)
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
