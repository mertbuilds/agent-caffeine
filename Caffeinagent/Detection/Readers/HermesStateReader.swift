import Foundation
import SQLite3

/// One row of `session_turn_leases` in the `state.db` of Hermes Agent.
struct HermesTurnLease: Equatable {
    /// The process that runs the turn, from `holder`.
    var pid: Int32
    var acquiredAt: Date
    var expiresAt: Date
}

/// `gateway_state.json`: what the messaging gateway says about itself.
struct HermesGatewayState: Equatable {
    var pid: Int32
    /// `gateway_state`: `starting`, `running`, `degraded`, `draining`,
    /// `stopped`, `startup_failed`.
    var state: String
    /// `active_agents`: the turns, cron jobs and API runs in progress.
    var activeAgents: Int

    /// The states in which the gateway runs turns.
    var serves: Bool { ["running", "degraded", "draining"].contains(state) }
}

/// What the files of one Hermes home say at one instant.
struct HermesHomeState: Equatable {
    /// Nil when `state.db` is there and could not be read.
    var leases: [HermesTurnLease]? = []
    var gateway: HermesGatewayState?
    /// The pids of `runtime/active_sessions.json`: the open chats.
    var openSessions: Set<Int32> = []
}

/// Reads what Hermes Agent writes about its turns
/// (docs/research/11-hermes-agent.md). All of it is in the Hermes home,
/// `~/.hermes`, and in each profile below `~/.hermes/profiles`:
///
/// - `state.db`, table `session_turn_leases(conversation_id, holder,
///   acquired_at, expires_at)`. Every turn takes a row before its first
///   model call and deletes it at its end, in the CLI, the gateway and
///   the desktop app alike. `holder` is `pid=<pid>:turn=<id>:platform=<name>`
///   and the times are epoch seconds. The row is renewed every 60 seconds
///   for 300 more.
/// - `gateway_state.json`, written by the gateway at every turn boundary
///   and once a minute: `pid`, `gateway_state`, `active_agents`.
/// - `runtime/active_sessions.json`: `entries` with the `pid` of each
///   open chat, also of one that has had no prompt.
///
/// Only pids, times, states and counts are read. No text of a
/// conversation is in these three places.
struct HermesStateReader {
    var home: URL

    static let database = "state.db"
    static let gatewayFile = "gateway_state.json"
    static let sessionsFile = "runtime/active_sessions.json"

    init(home: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hermes")) {
        self.home = home
    }

    /// The default home and the home of each profile.
    func homes() -> [URL] {
        let profiles = home.appendingPathComponent("profiles")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profiles.path)) ?? []
        return [home] + names.filter { !$0.hasPrefix(".") }.sorted().map { profiles.appendingPathComponent($0) }
    }

    // MARK: Parsing

    /// The pid of `pid=4242:pidns=7:turn=ab12:platform=cli`.
    nonisolated static func pid(ofHolder holder: String) -> Int32? {
        guard holder.hasPrefix("pid=") else { return nil }
        let digits = holder.dropFirst(4).prefix { $0.isNumber }
        guard let pid = Int32(digits), pid > 0 else { return nil }
        return pid
    }

    nonisolated static func gatewayState(_ data: Data) -> HermesGatewayState? {
        guard let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (record["pid"] as? NSNumber)?.int32Value, pid > 0,
              let state = record["gateway_state"] as? String else { return nil }
        let active = (record["active_agents"] as? NSNumber)?.intValue ?? 0
        return HermesGatewayState(pid: pid, state: state, activeAgents: max(0, active))
    }

    /// The file is `{"entries": [...]}`, and a bare list in older builds.
    nonisolated static func openSessions(_ data: Data) -> Set<Int32> {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries = (json as? [String: Any])?["entries"] as? [Any] ?? json as? [Any] ?? []
        return Set(entries.compactMap { (($0 as? [String: Any])?["pid"] as? NSNumber)?.int32Value }.filter { $0 > 0 })
    }

    // MARK: The database

    /// The rows of `session_turn_leases`, nil when the database or the
    /// table cannot be read.
    ///
    /// The database is in WAL mode, and a new row is in `state.db-wal`
    /// until the next checkpoint. A reader of the WAL uses `state.db-shm`:
    /// SQLite makes that file when it is missing, and a reader writes
    /// its place into it. This reader writes nothing in the folder of the
    /// agent. It opens `-shm` for reading only (`readonly_shm`), and with
    /// no WAL it opens the database file alone (`immutable`), which then
    /// holds every row. A WAL with no `-shm` is not read.
    nonisolated static func leases(inDatabase url: URL) -> [HermesTurnLease]? {
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
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT holder, acquired_at, expires_at FROM session_turn_leases", -1, &statement, nil) == SQLITE_OK else { return nil }
        var leases: [HermesTurnLease] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return leases }
            guard step == SQLITE_ROW else { return nil }
            guard let text = sqlite3_column_text(statement, 0), let pid = pid(ofHolder: String(cString: text)) else { continue }
            leases.append(HermesTurnLease(
                pid: pid,
                acquiredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            ))
        }
    }
}

/// What the Hermes homes say about one Hermes Agent process.
enum HermesSummary {
    /// A row is renewed every 60 seconds for 300 more, and a renewal can
    /// wait for the database. A row that ran out this long ago still
    /// counts for a process that lives: a turn that is read as over while
    /// it runs lets the Mac sleep.
    static let expiryGrace: TimeInterval = 120
    /// The start time of a process and the time of its first row come
    /// from two clocks.
    static let startMargin: TimeInterval = 2

    struct Reading: Equatable {
        var working = false
        /// When the oldest turn in progress took its row.
        var since: Date?
        /// The process is an open chat or the gateway, by the files.
        var listed = false
        /// Every database that is there was read.
        var readable = true
    }

    /// `pids` are the Hermes Agent processes of one instance and
    /// `started` is when its root started: a row of an earlier process
    /// with the same pid is not counted.
    static func reading(pids: Set<Int32>, started: Date, homes: [HermesHomeState], now: Date) -> Reading {
        var reading = Reading()
        for home in homes {
            if !home.openSessions.isDisjoint(with: pids) { reading.listed = true }
            if let gateway = home.gateway, pids.contains(gateway.pid) {
                reading.listed = true
                if gateway.serves, gateway.activeAgents > 0 { reading.working = true }
            }
            guard let leases = home.leases else {
                reading.readable = false
                continue
            }
            for lease in leases where pids.contains(lease.pid) {
                guard lease.acquiredAt >= started.addingTimeInterval(-startMargin),
                      now.timeIntervalSince(lease.expiresAt) < expiryGrace else { continue }
                reading.working = true
                reading.since = min(reading.since ?? lease.acquiredAt, lease.acquiredAt)
            }
        }
        return reading
    }

    /// Working while a turn of the process is in progress. Idle only for
    /// a process whose turns are known to be in the files: an open chat,
    /// the gateway, or a process that had a row before (`hadTurn`). Nil
    /// for any other: a one-shot run can be between its start and its
    /// first row.
    static func report(of reading: Reading, hadTurn: Bool, endedAt: Date?, now: Date) -> StateReport? {
        if reading.working {
            return StateReport(state: .working, since: reading.since, observedAt: now, source: .hermesState, detail: "in a turn")
        }
        guard reading.readable, reading.listed || hadTurn else { return nil }
        return StateReport(state: .idle, since: endedAt, observedAt: now, source: .hermesState, detail: nil)
    }
}
