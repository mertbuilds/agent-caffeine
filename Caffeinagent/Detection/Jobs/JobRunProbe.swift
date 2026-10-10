import Foundation

/// Tells from the processes whether the job of a hold runs. Pure.
///
/// - A launchd job runs while launchd lists a pid for its label.
/// - A crontab job runs while a process that cron started after the hold
///   opened has the stored name of the command. A line whose command has
///   no plain name ("cron job 3") is not looked for: any process of cron
///   could be it, and its start grace and its cap decide.
/// - A job of Hermes Agent is not looked for here. The detection engine
///   sees the agent work.
///
/// Privacy: the command line of a process is compared with the name and
/// kept nowhere.
enum JobRunMatch {
    static let cron = "/usr/sbin/cron"
    static let launchdPrefix = "launchd:"
    /// A process that started a moment before the hold opened still counts:
    /// two clocks are read one after the other.
    static let startTolerance: TimeInterval = 1
    private static let ancestorsLooked = 16

    /// The label to ask launchd for, nil for a hold of another source and
    /// for a label that would read as an option of the command.
    static func launchdLabel(of hold: JobHold) -> String? {
        guard hold.source == .launchd, hold.jobID.hasPrefix(launchdPrefix) else { return nil }
        let label = String(hold.jobID.dropFirst(launchdPrefix.count))
        return label.isEmpty || label.hasPrefix("-") ? nil : label
    }

    /// The name to look for among the processes of cron, nil when the
    /// line has no plain name.
    static func cronName(of hold: JobHold) -> String? {
        guard hold.source == .crontab, !hold.name.contains(" "), !hold.name.isEmpty else { return nil }
        return hold.name
    }

    /// What `launchctl list <label>` prints has the line `"PID" = 123;`
    /// while the job runs. The rest of the output is not looked at.
    static func launchdRuns(listOutput: String) -> Bool {
        listOutput.split(separator: "\n").contains { line in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "\"PID\"" else { return false }
            return Int(parts[1].dropLast(parts[1].hasSuffix(";") ? 1 : 0)).map { $0 > 0 } ?? false
        }
    }

    /// True while a process below cron that started after `since` is the
    /// command `name`: its binary has the name, or the first word of one
    /// of its first arguments does, as in `/bin/sh -c "backup.sh --all"`
    /// and `python3 backup.py`.
    static func cronJobRuns(name: String, since: TimeInterval, rows: [ProcessInfoRow]) -> Bool {
        let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.contains { row in
            guard row.startTime >= since - startTolerance, isNamed(row, name), row.executablePath != cron else { return false }
            var parent = byPid[row.ppid]
            for _ in 0..<ancestorsLooked {
                guard let current = parent else { return false }
                if current.executablePath == cron { return true }
                parent = byPid[current.ppid]
            }
            return false
        }
    }

    private static func isNamed(_ row: ProcessInfoRow, _ name: String) -> Bool {
        if (row.executablePath as NSString).lastPathComponent == name { return true }
        return row.arguments.prefix(3).contains { argument in
            let word = argument.drop(while: { $0 == " " }).prefix(while: { $0 != " " && $0 != "\t" })
            return (String(word) as NSString).lastPathComponent == name
        }
    }
}

/// The look at this Mac: the process table for the jobs of cron, and
/// `launchctl list` for the jobs of launchd. Both only read.
struct SystemJobRunProbe: JobRunProbing {
    static let timeout: TimeInterval = 2

    /// A test passes a script of its own.
    var launchctl = URL(fileURLWithPath: "/bin/launchctl")
    /// Nil when the process table could not be read.
    var rows: () -> [ProcessInfoRow]? = { SystemProcessCensus().snapshot() }

    func running(_ holds: [JobHold]) async -> [String: Bool] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: look(holds)) }
        }
    }

    /// Blocks while the command runs. Never on the main thread.
    func look(_ holds: [JobHold]) -> [String: Bool] {
        var running: [String: Bool] = [:]
        var table: [ProcessInfoRow]?
        var tableRead = false
        for hold in holds {
            if let label = JobRunMatch.launchdLabel(of: hold) {
                // A label that launchd does not know ends with a code that is not 0.
                guard case .ended(let status, let output, _) = JobCommand.run(launchctl, arguments: ["list", label], timeout: Self.timeout) else { continue }
                running[hold.id] = status == 0 && JobRunMatch.launchdRuns(listOutput: output)
            } else if let name = JobRunMatch.cronName(of: hold) {
                if !tableRead { (table, tableRead) = (rows(), true) }
                guard let rows = table else { continue }
                running[hold.id] = JobRunMatch.cronJobRuns(name: name, since: hold.start, rows: rows)
            }
        }
        return running
    }
}
