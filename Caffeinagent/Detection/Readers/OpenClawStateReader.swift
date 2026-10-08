import Foundation
import SQLite3

/// One row of `session_windows` with the status `running`.
struct OpenClawRun: Equatable {
    /// `started_at`.
    var startedAt: Date?
    /// The newest of `started_at`, `updated_at` and `transcript_updated_at`:
    /// the last time OpenClaw wrote the row or the transcript of the run.
    var renewedAt: Date?
}

/// What the database of one OpenClaw agent says at one instant.
struct OpenClawAgentState: Equatable {
    var runs: [OpenClawRun] = []
    /// The newest `ended_at` of a session that does not run.
    var endedAt: Date?
}

/// Reads what OpenClaw writes about the runs of its sessions
/// (docs/research/12-openclaw.md). Each agent of an OpenClaw home has a
/// database `agents/<agent id>/agent/openclaw-agent.sqlite` with the
/// table `session_windows`, one row per session:
///
///     status TEXT CHECK (status IS NULL OR status IN ('running', 'done', 'failed', 'killed', 'timeout'))
///     started_at INTEGER, ended_at INTEGER, updated_at INTEGER, transcript_updated_at INTEGER
///
/// The gateway sets `running` and `started_at` when a run of the session
/// starts, and `done`, `failed`, `killed` or `timeout` with `ended_at`
/// when it ends (`src/gateway/session-lifecycle-state.ts` in the
/// package). The times are epoch milliseconds.
///
/// Only the status and the four times are read. The text of a
/// conversation is in other tables.
struct OpenClawStateReader {
    var home: URL

    static let agentsFolder = "agents"
    static let database = "agent/openclaw-agent.sqlite"

    init(home: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".openclaw")) {
        self.home = home
    }

    /// The database of each agent that has one.
    func databases() -> [URL] {
        let agents = home.appendingPathComponent(Self.agentsFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: agents.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
            .map { agents.appendingPathComponent($0).appendingPathComponent(Self.database) }
            .filter { FileSignature(path: $0.path) != nil }
    }

    /// The runs in progress and the newest end, nil when the database or
    /// the table cannot be read.
    ///
    /// The database is in WAL mode and is opened as that of Hermes Agent
    /// is (`HermesStateReader.leases`): nothing is written in the folder
    /// of the agent, and a WAL with no `-shm` is not read.
    nonisolated static func state(inDatabase url: URL) -> OpenClawAgentState? {
        let wal = FileSignature(path: url.path + "-wal").map { $0.size > 0 } ?? false
        guard !wal || FileManager.default.fileExists(atPath: url.path + "-shm") else { return nil }
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = wal
            ? [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "readonly_shm", value: "1")]
            : [URLQueryItem(name: "immutable", value: "1")]
        guard let name = components.string else { return nil }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(name, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(database, 50)
        guard let running = rows(of: database, "SELECT started_at, updated_at, transcript_updated_at FROM session_windows WHERE status = 'running'"),
              let ended = rows(of: database, "SELECT max(ended_at) FROM session_windows WHERE status IS NOT 'running'") else { return nil }
        let runs = running.map { times in
            OpenClawRun(startedAt: times[0], renewedAt: times.compactMap { $0 }.max())
        }
        return OpenClawAgentState(runs: runs, endedAt: ended.first?[0])
    }

    /// Each row as its columns, read as times. Nil when the query fails.
    nonisolated private static func rows(of database: OpaquePointer?, _ query: String) -> [[Date?]]? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        var rows: [[Date?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { return nil }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else { return nil }
                let milliseconds = sqlite3_column_int64(statement, column)
                return milliseconds > 0 ? Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000) : nil
            })
        }
    }
}

/// What the databases of an OpenClaw home say about its gateway.
enum OpenClawSummary {
    /// A run that was killed with its process leaves a row that says
    /// `running` for ever. A row that OpenClaw did not write for this
    /// long says nothing any more, and the signs of activity decide: the
    /// same limit as for a hook working that nothing ends. OpenClaw
    /// writes the transcript at each message and each tool call, so only
    /// one tool call or one model wait that is longer than this is lost.
    static let runLimit = VerdictRules.hookWorkingLimit

    /// `states` holds one entry per database, nil for one that could not
    /// be read. Working while a run is in progress, idle only when every
    /// database was read. Nil with no database.
    static func report(of states: [OpenClawAgentState?], now: Date, limit: TimeInterval = runLimit) -> StateReport? {
        var since: Date?
        var working = false
        var ended: Date?
        for state in states.compactMap({ $0 }) {
            for run in state.runs {
                guard let renewed = run.renewedAt, now.timeIntervalSince(renewed) < limit else { continue }
                working = true
                if let started = run.startedAt { since = min(since ?? started, started) }
            }
            if let end = state.endedAt { ended = max(ended ?? end, end) }
        }
        if working {
            return StateReport(state: .working, since: since, observedAt: now, source: .openClawState, detail: "in a turn")
        }
        guard !states.isEmpty, !states.contains(where: { $0 == nil }) else { return nil }
        return StateReport(state: .idle, since: ended.flatMap { $0 <= now ? $0 : nil }, observedAt: now, source: .openClawState, detail: nil)
    }
}
