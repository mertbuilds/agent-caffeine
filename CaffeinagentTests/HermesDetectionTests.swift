import SQLite3
import XCTest

private final class FakeCensus: ProcessCensusing {
    var rows: [ProcessInfoRow] = []
    func snapshot() -> [ProcessInfoRow]? { rows }
}

private final class FakeAssertions: PowerAssertionListing {
    func assertingPIDs() -> Set<Int32> { [] }
}

private final class FakePower: PowerContextReading {
    func context() -> FrameContext { FrameContext() }
}

private final class FakeOpenFiles: OpenFileListing {
    func openFilePaths(of pid: Int32) -> [String]? { [] }
    func workingDirectory(of pid: Int32) -> String? { nil }
}

/// A `state.db` with the table of Hermes Agent's turn leases
/// (docs/research/11-hermes-agent.md) and made-up rows. The connection
/// stays open, as that of a running Hermes Agent does.
private final class LeaseDatabase {
    private var handle: OpaquePointer?
    let url: URL

    init(at url: URL, wal: Bool = true) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        if wal { run("PRAGMA journal_mode=WAL") }
        run("""
        CREATE TABLE IF NOT EXISTS session_turn_leases (
            conversation_id TEXT PRIMARY KEY,
            holder TEXT NOT NULL,
            acquired_at REAL NOT NULL,
            expires_at REAL NOT NULL
        )
        """)
    }

    deinit { sqlite3_close(handle) }

    func run(_ sql: String) {
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
    }

    func take(_ conversation: String, pid: Int32, platform: String = "cli", at: Date, expires: Date) {
        run("INSERT OR REPLACE INTO session_turn_leases VALUES ('\(conversation)', 'pid=\(pid):turn=t1:platform=\(platform)', \(at.timeIntervalSince1970), \(expires.timeIntervalSince1970))")
    }

    func renew(_ conversation: String, expires: Date) {
        run("UPDATE session_turn_leases SET expires_at = \(expires.timeIntervalSince1970) WHERE conversation_id = '\(conversation)'")
    }

    func release(_ conversation: String) {
        run("DELETE FROM session_turn_leases WHERE conversation_id = '\(conversation)'")
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }
}

/// The command `hermes` as it runs: Python with the launcher's source on
/// the command line. The source here is made up but for its last lines.
private enum Hermes {
    static let python = "/Users/me/.hermes/tools/python-3.14.7+20260901-darwin-arm64/bin/python3"
    static let source = "import os, re, sys\nsys.path.insert(0, '/Users/me/.hermes/hermes-agent')\nfrom hermes_cli.main import main\nsys.exit(main())\n"

    static func args(_ arguments: [String] = []) -> [String] { [python, "-I", "-c", source] + arguments }
}

final class HermesStateReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testThePidOfAHolder() {
        let cases: [(String, Int32?)] = [
            ("pid=4242:turn=ab12:platform=cli", 4242),
            ("pid=4242:pidns=4026531836:turn=ab12:platform=telegram", 4242),
            ("pid=7", 7),
            ("pid=:turn=x", nil),
            ("pid=0:turn=x", nil),
            ("turn=ab12:pid=4242", nil),
            ("", nil),
        ]
        for (holder, pid) in cases { XCTAssertEqual(HermesStateReader.pid(ofHolder: holder), pid, holder) }
    }

    func testTheGatewayFile() {
        let running = #"{"pid":900,"kind":"hermes-gateway","argv":["x","gateway","run"],"start_time":17,"gateway_state":"running","exit_reason":null,"restart_requested":false,"active_agents":2,"platforms":{},"updated_at":"2026-10-08T20:00:00+00:00"}"#
        XCTAssertEqual(HermesStateReader.gatewayState(Data(running.utf8)), HermesGatewayState(pid: 900, state: "running", activeAgents: 2))
        XCTAssertEqual(HermesStateReader.gatewayState(Data(#"{"pid":900,"gateway_state":"starting"}"#.utf8)), HermesGatewayState(pid: 900, state: "starting", activeAgents: 0))
        XCTAssertEqual(HermesStateReader.gatewayState(Data(#"{"pid":900,"gateway_state":"running","active_agents":-3}"#.utf8))?.activeAgents, 0)
        XCTAssertNil(HermesStateReader.gatewayState(Data(#"{"gateway_state":"running","active_agents":1}"#.utf8)), "No pid: nobody can say whose state it is")
        XCTAssertNil(HermesStateReader.gatewayState(Data(#"{"pid":900,"gateway_"#.utf8)), "Cut off")
        for (state, serves) in [("running", true), ("degraded", true), ("draining", true), ("starting", false), ("stopped", false), ("startup_failed", false)] {
            XCTAssertEqual(HermesGatewayState(pid: 1, state: state, activeAgents: 1).serves, serves, state)
        }
    }

    func testTheOpenChats() {
        let entries = #"{"entries":[{"lease_id":"a","session_id":"s1","surface":"cli","pid":700,"process_start_time":1.5,"started_at":2,"updated_at":3},{"lease_id":"b","session_id":"s2","surface":"desktop","pid":710},{"surface":"cli"},7]}"#
        XCTAssertEqual(HermesStateReader.openSessions(Data(entries.utf8)), [700, 710])
        XCTAssertEqual(HermesStateReader.openSessions(Data(#"[{"pid":5}]"#.utf8)), [5], "The older form is a bare list")
        XCTAssertEqual(HermesStateReader.openSessions(Data("{".utf8)), [])
    }

    func testTheRowsOfADatabaseThatIsOpen() throws {
        let database = try LeaseDatabase(at: root.appendingPathComponent("state.db"))
        XCTAssertEqual(HermesStateReader.leases(inDatabase: database.url), [])
        let taken = Date(timeIntervalSince1970: 1_791_300_010.5)
        database.take("c1", pid: 700, at: taken, expires: taken.addingTimeInterval(300))
        database.take("c2", pid: 900, platform: "telegram", at: taken.addingTimeInterval(1), expires: taken.addingTimeInterval(301))
        database.run("INSERT INTO session_turn_leases VALUES ('c3', 'someone', 1, 2)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.url.path + "-wal"), "The rows are in the WAL, as those of a running Hermes Agent are")
        XCTAssertEqual(Set(HermesStateReader.leases(inDatabase: database.url)?.map(\.pid) ?? []), [700, 900], "A holder with no pid is passed over")
        XCTAssertEqual(HermesStateReader.leases(inDatabase: database.url)?.first { $0.pid == 700 },
                       HermesTurnLease(pid: 700, acquiredAt: taken, expiresAt: taken.addingTimeInterval(300)))
        database.release("c1")
        XCTAssertEqual(HermesStateReader.leases(inDatabase: database.url)?.map(\.pid), [900])
    }

    /// A reader of a WAL writes its place into `-shm`: byte 104 changed
    /// at each read when this was measured with `mode=ro` alone. The
    /// database is written by another process here, as that of Hermes
    /// Agent is: inside one process SQLite shares the index, and the
    /// reader would write through the writer's.
    func testAReaderLeavesNoMarkInTheFilesOfTheAgent() throws {
        let url = root.appendingPathComponent("state.db")
        let writer = Process()
        let input = Pipe()
        writer.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        writer.arguments = [url.path]
        writer.standardInput = input
        writer.standardOutput = FileHandle.nullDevice
        try writer.run()
        // The writer stays open, as a running Hermes Agent does: its row is in the WAL.
        defer {
            try? input.fileHandleForWriting.close()
            writer.waitUntilExit()
        }
        input.fileHandleForWriting.write(Data("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE session_turn_leases (conversation_id TEXT PRIMARY KEY, holder TEXT NOT NULL, acquired_at REAL NOT NULL, expires_at REAL NOT NULL);
        INSERT INTO session_turn_leases VALUES ('c1', 'pid=700:turn=t1:platform=cli', 10, 310);

        """.utf8))
        let names = ["state.db", "state.db-shm", "state.db-wal"]
        let written = expectation(description: "the row is in the WAL")
        DispatchQueue.global().async {
            for _ in 0..<500 where (FileSignature(path: url.path + "-wal")?.size ?? 0) < 4096 * 3 { usleep(10_000) }
            written.fulfill()
        }
        wait(for: [written], timeout: 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), names)
        let before = try names.map { try Data(contentsOf: root.appendingPathComponent($0)) }
        XCTAssertEqual(HermesStateReader.leases(inDatabase: url)?.map(\.pid), [700])
        XCTAssertEqual(try names.map { try Data(contentsOf: root.appendingPathComponent($0)) }, before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), names)
    }

    /// The index of a WAL is gone and the WAL is not: the rows in it
    /// cannot be read without making a file.
    func testAWALWithNoIndexIsUnknown() throws {
        let database = try LeaseDatabase(at: root.appendingPathComponent("state.db"))
        database.take("c1", pid: 700, at: Date(timeIntervalSince1970: 10), expires: Date(timeIntervalSince1970: 310))
        let copy = root.appendingPathComponent("copy/state.db")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal"] { try FileManager.default.copyItem(atPath: database.url.path + suffix, toPath: copy.path + suffix) }
        XCTAssertNil(HermesStateReader.leases(inDatabase: copy))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copy.deletingLastPathComponent().path).sorted(), ["state.db", "state.db-wal"])
    }

    /// With no Hermes Agent running there is no WAL, and SQLite would make
    /// a `-shm` file to read one. Nothing is made in the agent's folder.
    /// The SQLite of macOS keeps the WAL of a database it closes, and that
    /// of Hermes Agent's Python does not, so this one is made with none.
    func testADatabaseThatIsClosedIsReadAndNoFileIsMade() throws {
        let database = try LeaseDatabase(at: root.appendingPathComponent("state.db"), wal: false)
        database.take("c1", pid: 700, at: Date(timeIntervalSince1970: 10), expires: Date(timeIntervalSince1970: 310))
        database.close()
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(before, ["state.db"])
        XCTAssertEqual(HermesStateReader.leases(inDatabase: database.url)?.map(\.pid), [700])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
    }

    func testADatabaseThatCannotBeReadIsUnknown() throws {
        let other = root.appendingPathComponent("other.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(other.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE sessions (id TEXT)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        XCTAssertNil(HermesStateReader.leases(inDatabase: other), "An older Hermes Agent with no lease table")
        let broken = root.appendingPathComponent("broken.db")
        try Data("this is no database, and it is long enough to be read as one page of it".utf8).write(to: broken)
        XCTAssertNil(HermesStateReader.leases(inDatabase: broken))
        XCTAssertNil(HermesStateReader.leases(inDatabase: root.appendingPathComponent("missing.db")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["broken.db", "other.db"])
    }

    func testTheHomesAreTheDefaultOneAndEachProfile() throws {
        let reader = HermesStateReader(home: root)
        XCTAssertEqual(reader.homes(), [root])
        for name in ["work", "bot", ".hidden"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("profiles/\(name)"), withIntermediateDirectories: true)
        }
        XCTAssertEqual(reader.homes().map(\.lastPathComponent), [root.lastPathComponent, "bot", "work"])
    }

    func testSummary() {
        let now = Date(timeIntervalSince1970: 1_791_300_000)
        let started = now.addingTimeInterval(-600)
        func lease(_ pid: Int32, taken: TimeInterval, expires: TimeInterval) -> HermesTurnLease {
            HermesTurnLease(pid: pid, acquiredAt: now.addingTimeInterval(taken), expiresAt: now.addingTimeInterval(expires))
        }
        typealias Reading = HermesSummary.Reading
        let cases: [(name: String, homes: [HermesHomeState], want: Reading)] = [
            ("no home", [], Reading()),
            ("an open chat", [HermesHomeState(openSessions: [700])], Reading(listed: true)),
            ("the chat of another process", [HermesHomeState(openSessions: [701])], Reading()),
            ("a turn", [HermesHomeState(leases: [lease(700, taken: -50, expires: 250)])], Reading(working: true, since: now.addingTimeInterval(-50))),
            ("two turns: the older start", [HermesHomeState(leases: [lease(700, taken: -50, expires: 250), lease(700, taken: -90, expires: 200)])],
             Reading(working: true, since: now.addingTimeInterval(-90))),
            ("the turn of another process", [HermesHomeState(leases: [lease(701, taken: -50, expires: 250)])], Reading()),
            ("a row that ran out a moment ago", [HermesHomeState(leases: [lease(700, taken: -400, expires: -100)])],
             Reading(working: true, since: now.addingTimeInterval(-400))),
            ("a row that ran out long ago", [HermesHomeState(leases: [lease(700, taken: -500, expires: -121)])], Reading()),
            ("a row of an earlier process with this pid", [HermesHomeState(leases: [lease(700, taken: -700, expires: 100)])], Reading()),
            ("a database that cannot be read", [HermesHomeState(leases: nil, openSessions: [700])], Reading(listed: true, readable: false)),
            ("a turn in the second home", [HermesHomeState(), HermesHomeState(leases: [lease(700, taken: -5, expires: 295)])],
             Reading(working: true, since: now.addingTimeInterval(-5))),
            ("the gateway at rest", [HermesHomeState(gateway: HermesGatewayState(pid: 700, state: "running", activeAgents: 0))], Reading(listed: true)),
            ("the gateway counts a turn", [HermesHomeState(gateway: HermesGatewayState(pid: 700, state: "running", activeAgents: 1))], Reading(working: true, listed: true)),
            ("the count of a gateway that stopped", [HermesHomeState(gateway: HermesGatewayState(pid: 700, state: "stopped", activeAgents: 1))], Reading(listed: true)),
            ("the gateway of another process", [HermesHomeState(gateway: HermesGatewayState(pid: 9, state: "running", activeAgents: 3))], Reading()),
        ]
        for c in cases {
            XCTAssertEqual(HermesSummary.reading(pids: [700], started: started, homes: c.homes, now: now), c.want, c.name)
        }

        let working = StateReport(state: .working, since: now.addingTimeInterval(-50), observedAt: now, source: .hermesState, detail: "in a turn")
        XCTAssertEqual(HermesSummary.report(of: Reading(working: true, since: now.addingTimeInterval(-50)), hadTurn: false, endedAt: nil, now: now), working)
        XCTAssertEqual(HermesSummary.report(of: Reading(working: true, since: now.addingTimeInterval(-50), readable: false), hadTurn: false, endedAt: nil, now: now), working,
                       "A turn that was read counts, also when another database was not")
        let idle = StateReport(state: .idle, since: nil, observedAt: now, source: .hermesState, detail: nil)
        XCTAssertEqual(HermesSummary.report(of: Reading(listed: true), hadTurn: false, endedAt: nil, now: now), idle)
        XCTAssertEqual(HermesSummary.report(of: Reading(), hadTurn: true, endedAt: now.addingTimeInterval(-3), now: now)?.since, now.addingTimeInterval(-3))
        XCTAssertNil(HermesSummary.report(of: Reading(), hadTurn: false, endedAt: nil, now: now), "A run that is not listed can be before its first row")
        XCTAssertNil(HermesSummary.report(of: Reading(listed: true, readable: false), hadTurn: true, endedAt: nil, now: now), "Idle is said only when every database was read")
    }
}

final class HermesCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow
    private let catalog = AgentCatalog.standard
    private let homebrewPython = "/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"

    func testMatch() {
        let venv = "/Users/me/.local/share/uv/tools/hermes-agent/bin/python"
        let cases: [(name: String, path: String, args: [String], role: AgentRole?)] = [
            ("the chat, as the launcher starts it", Hermes.python, Hermes.args(), .session),
            ("a chat with a prompt", Hermes.python, Hermes.args(["chat", "-q", "say hi"]), .session),
            ("a resumed chat", Hermes.python, Hermes.args(["--resume", "abc"]), .session),
            ("the gateway", Hermes.python, Hermes.args(["gateway", "run", "--replace"]), .engine),
            ("the gateway of a profile", Hermes.python, Hermes.args(["--profile", "bot", "gateway", "run"]), .engine),
            ("the gateway of the service", Hermes.python, Hermes.args(["gateway", "run", "--external-supervisor"]), .engine),
            ("what stamps the error log of the gateway", Hermes.python,
             Hermes.args(["--run-module", "hermes_cli.stderr_timestamp", "--error-log", "/Users/me/.hermes/logs/gateway.error.log", "--", "/Users/me/.hermes/hermes-agent/.hermes/bin/hermes", "gateway", "run", "--external-supervisor"]), .helper),
            ("the state of the gateway", Hermes.python, Hermes.args(["gateway", "status"]), .helper),
            ("the gateway service is started", Hermes.python, Hermes.args(["gateway", "start"]), .helper),
            ("the setup", Hermes.python, Hermes.args(["setup"]), nil),
            ("an update", Hermes.python, Hermes.args(["update"]), nil),
            ("the plugins", Hermes.python, Hermes.args(["plugins", "list"]), nil),
            ("the cron runner", Hermes.python, Hermes.args(["cron", "tick"]), .session),
            ("the launcher with the Python of Homebrew", homebrewPython, [homebrewPython, "-I", "-c", Hermes.source, "chat"], .session),
            ("installed by pip", venv, [venv, "/Users/me/.local/bin/hermes"], .session),
            ("installed by pip: the gateway", venv, [venv, "/Users/me/.local/bin/hermes", "gateway", "run"], .engine),
            ("installed by pip: the doctor", venv, [venv, "/Users/me/.local/bin/hermes", "doctor"], nil),
            ("as a module", venv, [venv, "-m", "hermes_cli.main", "chat"], .session),
            ("the older command", venv, [venv, "/Users/me/.local/bin/hermes-agent"], .session),
            ("the older command by its name", "/usr/local/bin/hermes-agent", ["hermes-agent"], .session),

            // Other software with the name.
            ("the JavaScript engine of React Native", "/Users/me/app/ios/Pods/hermes-engine/destroot/bin/hermes", ["hermes", "-O", "index.js"], nil),
            ("its compiler", "/Users/me/app/node_modules/react-native/sdks/hermesc/osx-bin/hermesc", ["hermesc", "-emit-binary", "-out", "a.hbc", "a.js"], nil),
            ("the JavaScript engine from Homebrew", "/opt/homebrew/bin/hermes", ["hermes"], nil),
            ("a messaging app", "/Applications/Hermes.app/Contents/MacOS/Hermes", ["/Applications/Hermes.app/Contents/MacOS/Hermes"], nil),
            ("the installer of Hermes Agent", "/Applications/Hermes.app/Contents/MacOS/Hermes-Setup", ["/Applications/Hermes.app/Contents/MacOS/Hermes-Setup"], nil),
            ("the installer's Python", homebrewPython, [homebrewPython, "-I", "-B", "/Users/me/.hermes/hermes-agent/pm/launch.py", "install"], nil),
            ("a script of the user", "/usr/bin/python3", ["python3", "hermes.py"], nil),
            ("other source on the command line", Hermes.python, [Hermes.python, "-c", "import hermes; print(1)"], nil),
            ("a tool of Hermes Agent in its Python", Hermes.python, [Hermes.python, "/Users/me/.hermes/hermes-agent/mcp_serve.py"], nil),
            ("uv of Hermes Agent", "/Users/me/.hermes/tools/uv-0.12.3-darwin-arm64/uv", ["uv", "sync"], nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: c.path, args: c.args), userNames: [])
            XCTAssertEqual(match?.role, c.role, c.name)
            if c.role != nil { XCTAssertEqual(match?.definition.id, "hermes-agent", c.name) }
        }
        let definition = catalog.definitions.first { $0.id == AgentCatalog.hermesID }
        XCTAssertEqual(definition?.displayName, "Hermes Agent")
        XCTAssertEqual(definition?.level, .state)
        XCTAssertEqual(definition?.kind, .cli)
        XCTAssertEqual(definition?.processNames, ["hermes-agent"], "The name the old list knew, and no other")
        XCTAssertEqual(AgentCatalog.version, 8)
    }

    /// The arguments are those after the source, so the command decides.
    func testTheCommandOfSourceOnTheCommandLine() {
        let command = AgentCatalog.command(of: .fixture(10, path: Hermes.python, args: Hermes.args(["gateway", "run"])))
        XCTAssertEqual(command.arguments, ["gateway", "run"])
        XCTAssertEqual(command.inlineSource, Hermes.source)
        XCTAssertTrue(command.interpreterRunsScript)
        let joined = AgentCatalog.command(of: .fixture(10, path: Hermes.python, args: [Hermes.python, "-Ic", "print(1)", "x"]))
        XCTAssertEqual(joined.inlineSource, "print(1)")
        XCTAssertEqual(joined.arguments, ["x"])
        let script = AgentCatalog.command(of: .fixture(10, path: Hermes.python, args: [Hermes.python, "-I", "tool.py", "-c", "x"]))
        XCTAssertNil(script.inlineSource, "A flag after the script is the script's")
        XCTAssertNil(AgentCatalog.command(of: .fixture(10, path: "/opt/homebrew/bin/node", args: ["node", "-c", "x.js"])).inlineSource)
    }

    /// A tool call is a child of the one process. A worker that the
    /// gateway starts is a session of its own.
    func testInstances() {
        let rows: [Row] = [
            .fixture(700, path: Hermes.python, args: Hermes.args()),
            .fixture(710, ppid: 700, path: "/bin/bash", args: ["bash", "-c", "sleep 400"]),
            .fixture(711, ppid: 710, path: "/bin/sleep", args: ["sleep", "400"]),
            .fixture(890, path: Hermes.python, args: Hermes.args(["--run-module", "hermes_cli.stderr_timestamp", "--", "/Users/me/.local/bin/hermes", "gateway", "run"])),
            .fixture(900, ppid: 890, path: Hermes.python, args: Hermes.args(["gateway", "run", "--replace"])),
            .fixture(910, ppid: 900, path: Hermes.python, args: Hermes.args(["chat", "-q", "task"])),
            .fixture(950, path: Hermes.python, args: Hermes.args(["setup"])),
            .fixture(960, path: "/Applications/Hermes.app/Contents/MacOS/Hermes-Setup", args: ["/Applications/Hermes.app/Contents/MacOS/Hermes-Setup"]),
        ]
        let instances = catalog.instances(in: rows)
        XCTAssertEqual(instances.map(\.rootPID).sorted(), [700, 900, 910])
        XCTAssertEqual(instances.first { $0.rootPID == 700 }?.rows.map(\.pid), [700, 710, 711])
        XCTAssertEqual(instances.first { $0.rootPID == 900 }?.role, .engine)
        XCTAssertEqual(instances.first { $0.rootPID == 910 }?.role, .session)
    }
}

final class HermesTimelineTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }

    private var root: URL!
    private var census: FakeCensus!
    private var collector: EvidenceCollector!
    private var database: LeaseDatabase!
    private var seconds: TimeInterval = 0
    private var agentMemory: [ProcessIdentity: AgentMemory] = [:]
    private var reducer = AgentNoticeReducer()
    private var told: [(at: TimeInterval, notice: AgentNotice)] = []
    private var settings = DetectionSettings()

    struct Step {
        var evidence: AgentEvidence?
        var reading: AgentReading?
        var watched: Set<String>
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hermes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        census = FakeCensus()
        var sources = EvidenceCollector.Sources(census: census, assertions: FakeAssertions(), power: FakePower(), openFiles: FakeOpenFiles())
        sources.hermesState = HermesStateReader(home: root)
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
        database = try LeaseDatabase(at: root.appendingPathComponent("state.db"))
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private func hermes(_ pid: Int32, _ arguments: [String] = [], cpu: TimeInterval = 0) -> Row {
        .fixture(pid, start: processStart, path: Hermes.python, args: Hermes.args(arguments), cpu: cpu)
    }

    /// The shell of a tool call with a command below it that uses no CPU.
    private func command(below pid: Int32) -> [Row] {
        [
            .fixture(pid + 10, ppid: pid, start: processStart + 500, path: "/bin/bash", args: ["bash", "-c", "sleep 400"]),
            .fixture(pid + 11, ppid: pid + 10, start: processStart + 500, path: "/bin/sleep", args: ["sleep", "400"]),
        ]
    }

    private func write(_ text: String, to name: String) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func openChat(_ pids: Int32...) throws {
        let entries = pids.map { "{\"lease_id\":\"l\($0)\",\"session_id\":\"s\($0)\",\"surface\":\"cli\",\"pid\":\($0)}" }.joined(separator: ",")
        try write("{\"entries\":[\(entries)]}", to: HermesStateReader.sessionsFile)
    }

    /// As the gateway writes it at a turn boundary and once a minute.
    private func gateway(pid: Int32 = 900, state: String = "running", active: Int, at seconds: TimeInterval) throws {
        try write("{\"pid\":\(pid),\"kind\":\"hermes-gateway\",\"gateway_state\":\"\(state)\",\"active_agents\":\(active),\"updated_at\":\"t\(Int(seconds))\"}",
                  to: HermesStateReader.gatewayFile)
    }

    @discardableResult
    private func step(_ seconds: TimeInterval, pid: Int32 = 700) -> Step {
        self.seconds = seconds
        let sample = collector.collect()
        let (readings, memory) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
        agentMemory = memory
        let notices = reducer.update(AgentNoticeInput(readings: readings, settings: AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: false)), now: sample.frame.at)
        told += notices.map { (seconds, $0) }
        return Step(evidence: sample.frame.agents.first { $0.pid == pid }, reading: readings.first { $0.identity.pid == pid }, watched: sample.watchedFiles)
    }

    @discardableResult
    private func run(_ range: ClosedRange<Int>, by stride: Int = 1, pid: Int32 = 700, before: ((Int) throws -> Void)? = nil, check: ((Step, Int) -> Void)? = nil) rethrows -> Step {
        var last: Step?
        for second in Swift.stride(from: range.lowerBound, through: range.upperBound, by: stride) {
            try before?(second)
            let step = step(TimeInterval(second), pid: pid)
            check?(step, second)
            last = step
        }
        return last!
    }

    /// A chat in a terminal: a prompt, a tool call that is quiet for 400
    /// seconds, and the end.
    func testAPromptAQuietToolCallAndTheEnd() throws {
        census.rows = [hermes(700)]
        try openChat(700)
        let open = run(0...9)
        XCTAssertEqual(open.evidence?.agentID, "hermes-agent")
        XCTAssertEqual(open.evidence?.displayName, "Hermes Agent")
        XCTAssertEqual(open.evidence?.role, .session)
        XCTAssertEqual(open.evidence?.level, .state)
        XCTAssertEqual(open.evidence?.reported, StateReport(state: .idle, since: nil, observedAt: at(9), source: .hermesState, detail: nil))
        XCTAssertEqual(open.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertTrue(open.watched.contains { $0.hasSuffix("/state.db-wal") }, "A new row brings the next sample at once")

        database.take("c1", pid: 700, at: at(10), expires: at(310))
        census.rows = [hermes(700)] + command(below: 700)
        let began = step(10)
        XCTAssertEqual(began.evidence?.reported, StateReport(state: .working, since: at(10), observedAt: at(10), source: .hermesState, detail: "in a turn"))
        XCTAssertEqual(began.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertEqual(began.reading?.turn, AgentTurn(state: .working, since: at(10)))

        // No CPU for 400 seconds. The row is renewed once a minute.
        try run(11...416, before: { second in
            if (second - 10) % 60 == 0 { self.database.renew("c1", expires: self.at(TimeInterval(second) + 300)) }
        }, check: { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)")
            XCTAssertEqual(step.reading?.turn, AgentTurn(state: .working, since: self.at(10)), "\(second)")
            XCTAssertEqual(step.evidence?.childCommands, 1, "\(second)")
        })
        XCTAssertTrue(told.isEmpty)

        database.release("c1")
        census.rows = [hermes(700)]
        let ended = step(417)
        XCTAssertEqual(ended.evidence?.reported, StateReport(state: .idle, since: at(417), observedAt: at(417), source: .hermesState, detail: nil))
        XCTAssertEqual(ended.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertEqual(ended.reading?.turn, AgentTurn(state: .idle))
        run(418...500) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
        XCTAssertEqual(told.first?.notice.sessions.first?.workedFor ?? 0, 407, accuracy: 0.5)
    }

    /// The gateway is up for three hours and no message comes. It writes
    /// its state once a minute and uses the processor in bursts.
    func testAGatewayThatIsOnlyUpNeverWorks() throws {
        var cpu: TimeInterval = 0
        try run(0...10_800, by: 5, pid: 900, before: { second in
            if second % 60 == 0 {
                try self.gateway(active: 0, at: TimeInterval(second))
                cpu += 1.5
            }
            if second % 1800 < 60 { cpu += 0.4 }
            self.census.rows = [self.hermes(900, ["gateway", "run", "--replace"], cpu: cpu)]
        }, check: { step, second in
            XCTAssertEqual(step.evidence?.role, .engine, "\(second)")
            XCTAssertEqual(step.evidence?.level, .state, "\(second)")
            XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt), "\(second)")
        })
        XCTAssertTrue(told.isEmpty)
    }

    /// A message comes in, the turn runs for 100 seconds, and a cron job
    /// calls a model for 20 seconds later: work only while each runs.
    func testATurnInsideTheGateway() throws {
        census.rows = [hermes(900, ["gateway", "run"])]
        try gateway(active: 0, at: 0)
        XCTAssertEqual(run(0...29, pid: 900).reading?.verdict.state, .idle)

        database.take("telegram:1", pid: 900, platform: "telegram", at: at(30), expires: at(330))
        try gateway(active: 1, at: 30)
        let began = step(30, pid: 900)
        XCTAssertEqual(began.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertEqual(began.reading?.turn, AgentTurn(state: .working, since: at(30)))
        try run(31...129, pid: 900, before: { second in
            if second % 60 == 0 { try self.gateway(active: 1, at: TimeInterval(second)) }
        }, check: { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") })

        database.release("telegram:1")
        try gateway(active: 0, at: 130)
        let ended = step(130, pid: 900)
        XCTAssertEqual(ended.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        run(131...599, pid: 900) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])

        // The cron job has no row of a chat: the count of the gateway says it.
        try gateway(active: 1, at: 600)
        run(600...619, pid: 900) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        try gateway(active: 0, at: 620)
        run(620...700, pid: 900) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished, .finished])
    }

    /// A run that is no open chat (`hermes chat -q`) says nothing until
    /// its first row: the signs of activity decide, as before. After its
    /// turn it is known, and its idle is said.
    func testARunThatIsNotListed() throws {
        census.rows = [hermes(700, ["chat", "-q", "task"])]
        let before = run(0...9)
        XCTAssertEqual(before.evidence?.level, .activity)
        XCTAssertNil(before.evidence?.reported)
        XCTAssertEqual(before.reading?.verdict.confidence, .inferredWeak)

        database.take("c1", pid: 700, at: at(10), expires: at(310))
        XCTAssertEqual(run(10...40).reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        database.release("c1")
        let after = run(41...60)
        XCTAssertEqual(after.evidence?.level, .state)
        XCTAssertEqual(after.evidence?.reported?.since, at(41))
        XCTAssertEqual(after.reading?.verdict.state, .idle)
    }

    /// Two chats and the gateway share one database: the row names its process.
    func testTheTurnOfOneProcessIsNotTheTurnOfAnother() throws {
        census.rows = [hermes(700), hermes(701), hermes(900, ["gateway", "run"])]
        try openChat(700, 701)
        try gateway(active: 0, at: 0)
        database.take("c1", pid: 701, at: at(0), expires: at(300))
        for pid: Int32 in [700, 900] { XCTAssertEqual(run(0...5, pid: pid).reading?.verdict.state, .idle, "\(pid)") }
        XCTAssertEqual(step(6, pid: 701).reading?.verdict.state, .working)
    }

    /// A Hermes Agent that was killed in a turn leaves its row, and the
    /// next process can get its pid.
    func testARowFromBeforeTheProcessStartedIsNotCounted() throws {
        census.rows = [hermes(700)]
        try openChat(700)
        database.take("c1", pid: 700, at: Date(timeIntervalSince1970: processStart - 100), expires: at(200))
        XCTAssertEqual(run(0...9).reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
    }

    /// The renewal of a row can be late. A row that ran out a short time
    /// ago still holds, and one that nobody renews lets go.
    func testARowThatIsNotRenewed() throws {
        census.rows = [hermes(700)]
        try openChat(700)
        database.take("c1", pid: 700, at: at(0), expires: at(300))
        run(0...419) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        XCTAssertEqual(run(420...430).reading?.verdict.state, .idle)
    }

    /// With no `state.db` that can be read, nothing is said and the signs
    /// of activity decide.
    func testADatabaseThatCannotBeRead() throws {
        database.close()
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: database.url.path + suffix) }
        try Data("this is no database, and it is long enough to be read as one page of it".utf8).write(to: database.url)
        census.rows = [hermes(700)]
        try openChat(700)
        let step = run(0...9)
        XCTAssertEqual(step.evidence?.level, .activity)
        XCTAssertNil(step.evidence?.reported)
    }
}
