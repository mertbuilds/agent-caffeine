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

/// The database of one OpenClaw agent with the columns of
/// `session_windows` that are read (docs/research/12-openclaw.md) and
/// made-up rows. The connection stays open, as that of a running gateway
/// does.
private final class SessionDatabase {
    private var handle: OpaquePointer?
    let url: URL

    init(at url: URL, wal: Bool = true) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        if wal { run("PRAGMA journal_mode=WAL") }
        run("""
        CREATE TABLE IF NOT EXISTS session_windows (
            session_id TEXT NOT NULL PRIMARY KEY,
            updated_at INTEGER NOT NULL,
            transcript_updated_at INTEGER DEFAULT NULL,
            started_at INTEGER,
            ended_at INTEGER,
            status TEXT CHECK (status IS NULL OR status IN ('running', 'done', 'failed', 'killed', 'timeout'))
        ) STRICT
        """)
    }

    deinit { sqlite3_close(handle) }

    func run(_ sql: String) {
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK, sql)
    }

    private static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// A session that has had no run.
    func create(_ session: String, at: Date) {
        run("INSERT INTO session_windows (session_id, updated_at) VALUES ('\(session)', \(Self.milliseconds(at)))")
    }

    func start(_ session: String, at: Date) {
        let time = Self.milliseconds(at)
        run("INSERT OR REPLACE INTO session_windows (session_id, updated_at, started_at, ended_at, status) VALUES ('\(session)', \(time), \(time), NULL, 'running')")
    }

    /// A message or a tool call of the run is written to the transcript.
    func write(_ session: String, at: Date) {
        run("UPDATE session_windows SET transcript_updated_at = \(Self.milliseconds(at)) WHERE session_id = '\(session)'")
    }

    func end(_ session: String, status: String = "done", at: Date) {
        let time = Self.milliseconds(at)
        run("UPDATE session_windows SET status = '\(status)', ended_at = \(time), updated_at = \(time) WHERE session_id = '\(session)'")
    }

    func close() {
        sqlite3_close(handle)
        handle = nil
    }
}

final class OpenClawStateReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("openclaw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_791_300_000 + seconds) }

    func testARunThatIsInProgressAndOneThatEnded() throws {
        let database = try SessionDatabase(at: root.appendingPathComponent("openclaw-agent.sqlite"))
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url), OpenClawAgentState())
        database.create("new", at: at(1))
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url), OpenClawAgentState(), "A session with no run has no status")
        database.start("s1", at: at(10.5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.url.path + "-wal"), "The rows are in the WAL, as those of a running gateway are")
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url),
                       OpenClawAgentState(runs: [OpenClawRun(startedAt: at(10.5), renewedAt: at(10.5))]))
        database.write("s1", at: at(40))
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url)?.runs, [OpenClawRun(startedAt: at(10.5), renewedAt: at(40))])
        database.end("s1", at: at(50))
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url), OpenClawAgentState(endedAt: at(50)))
        for (index, status) in ["failed", "killed", "timeout"].enumerated() {
            database.start("s1", at: at(60 + TimeInterval(index) * 10))
            XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url)?.runs.count, 1, status)
            database.end("s1", status: status, at: at(65 + TimeInterval(index) * 10))
            XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url), OpenClawAgentState(endedAt: at(65 + TimeInterval(index) * 10)), status)
        }
    }

    /// With no gateway running there is no WAL, and SQLite would make a
    /// `-shm` file to read one. Nothing is made in the agent's folder.
    func testADatabaseThatIsClosedIsReadAndNoFileIsMade() throws {
        let database = try SessionDatabase(at: root.appendingPathComponent("openclaw-agent.sqlite"), wal: false)
        database.start("s1", at: at(10))
        database.close()
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(before, ["openclaw-agent.sqlite"])
        XCTAssertEqual(OpenClawStateReader.state(inDatabase: database.url)?.runs.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
    }

    /// The index of a WAL is gone and the WAL is not: the rows in it
    /// cannot be read without making a file.
    func testAWALWithNoIndexIsUnknown() throws {
        let database = try SessionDatabase(at: root.appendingPathComponent("openclaw-agent.sqlite"))
        database.start("s1", at: at(10))
        let copy = root.appendingPathComponent("copy/openclaw-agent.sqlite")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal"] { try FileManager.default.copyItem(atPath: database.url.path + suffix, toPath: copy.path + suffix) }
        XCTAssertNil(OpenClawStateReader.state(inDatabase: copy))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copy.deletingLastPathComponent().path).sorted(),
                       ["openclaw-agent.sqlite", "openclaw-agent.sqlite-wal"])
    }

    func testADatabaseThatCannotBeReadIsUnknown() throws {
        let other = root.appendingPathComponent("other.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(other.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE session_nodes (session_key TEXT)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        XCTAssertNil(OpenClawStateReader.state(inDatabase: other), "Another OpenClaw with no such table")
        let broken = root.appendingPathComponent("broken.sqlite")
        try Data("this is no database, and it is long enough to be read as one page of it".utf8).write(to: broken)
        XCTAssertNil(OpenClawStateReader.state(inDatabase: broken))
        XCTAssertNil(OpenClawStateReader.state(inDatabase: root.appendingPathComponent("missing.sqlite")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["broken.sqlite", "other.sqlite"])
    }

    func testTheDatabasesAreThoseOfTheAgentsThatHaveOne() throws {
        let reader = OpenClawStateReader(home: root)
        XCTAssertEqual(reader.databases(), [], "No agents folder")
        for name in ["writer", "coordinator", ".hidden"] {
            _ = try SessionDatabase(at: root.appendingPathComponent("agents/\(name)/agent/openclaw-agent.sqlite"), wal: false)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agents/reviewer/sessions"), withIntermediateDirectories: true)
        XCTAssertEqual(reader.databases().map { $0.pathComponents.suffix(3).joined(separator: "/") },
                       ["coordinator/agent/openclaw-agent.sqlite", "writer/agent/openclaw-agent.sqlite"])
    }

    func testSummary() {
        let now = at(10_000)
        let limit = OpenClawSummary.runLimit
        func run(started: TimeInterval, renewed: TimeInterval) -> OpenClawRun { OpenClawRun(startedAt: at(started), renewedAt: at(renewed)) }
        func report(_ states: [OpenClawAgentState?]) -> StateReport? { OpenClawSummary.report(of: states, now: now) }
        func said(_ state: ReportedState, since: Date?, detail: String? = nil) -> StateReport {
            StateReport(state: state, since: since, observedAt: now, source: .openClawState, detail: detail)
        }

        XCTAssertNil(report([]), "No database: nothing is said")
        XCTAssertEqual(report([OpenClawAgentState()]), said(.idle, since: nil))
        XCTAssertEqual(report([OpenClawAgentState(endedAt: at(9000)), OpenClawAgentState(endedAt: at(9500))]), said(.idle, since: at(9500)))
        XCTAssertEqual(report([OpenClawAgentState(runs: [run(started: 9900, renewed: 9950)], endedAt: at(9000))]),
                       said(.working, since: at(9900), detail: "in a turn"))
        XCTAssertEqual(report([OpenClawAgentState(runs: [run(started: 9900, renewed: 9900)]), OpenClawAgentState(runs: [run(started: 9000, renewed: 9990)])]),
                       said(.working, since: at(9000), detail: "in a turn"), "The oldest run in progress")
        // A row that nobody wrote for the limit says nothing any more.
        XCTAssertEqual(report([OpenClawAgentState(runs: [run(started: 100, renewed: 10_000 - limit + 1)])])?.state, .working)
        XCTAssertEqual(report([OpenClawAgentState(runs: [run(started: 100, renewed: 10_000 - limit)], endedAt: at(50))]), said(.idle, since: at(50)))
        XCTAssertEqual(report([OpenClawAgentState(runs: [OpenClawRun(startedAt: nil, renewedAt: nil)])])?.state, .idle, "A row with no time")
        // A database that cannot be read: a run of another one counts, idle is not said.
        XCTAssertNil(report([OpenClawAgentState(), nil]))
        XCTAssertEqual(report([OpenClawAgentState(runs: [run(started: 9900, renewed: 9900)]), nil])?.state, .working)
        XCTAssertEqual(report([OpenClawAgentState(endedAt: at(10_500))]), said(.idle, since: nil), "An end from ahead of the clock")
    }
}

/// The gateway of OpenClaw is judged by the state of its sessions, and
/// its own CPU use is no sign of work (docs/research/12-openclaw.md).
final class OpenClawTimelineTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }
    private let node = "/opt/homebrew/Cellar/node/26.8.1/bin/node"

    private var root: URL!
    private var census: FakeCensus!
    private var collector: EvidenceCollector!
    private var seconds: TimeInterval = 0
    private var agentMemory: [ProcessIdentity: AgentMemory] = [:]
    private var settings = DetectionSettings()

    struct Step {
        var evidence: AgentEvidence?
        var reading: AgentReading?
        var watched: Set<String>
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("openclaw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        census = FakeCensus()
        var sources = EvidenceCollector.Sources(census: census, assertions: FakeAssertions(), power: FakePower(), openFiles: FakeOpenFiles())
        sources.openClawState = OpenClawStateReader(home: root)
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private func database(_ agent: String = "coordinator") throws -> SessionDatabase {
        try SessionDatabase(at: root.appendingPathComponent("agents/\(agent)/agent/openclaw-agent.sqlite"))
    }

    private func gateway(cpu: TimeInterval = 0) -> Row {
        .fixture(900, start: processStart, path: node, args: ["openclaw-gateway"], cpu: cpu)
    }

    @discardableResult
    private func step(_ seconds: TimeInterval, pid: Int32 = 900) -> Step {
        self.seconds = seconds
        let sample = collector.collect()
        let (readings, memory) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
        agentMemory = memory
        return Step(evidence: sample.frame.agents.first { $0.pid == pid }, reading: readings.first { $0.identity.pid == pid }, watched: sample.watchedFiles)
    }

    @discardableResult
    private func run(_ range: ClosedRange<Int>, by stride: Int = 1, pid: Int32 = 900, before: ((Int) throws -> Void)? = nil, check: ((Step, Int) -> Void)? = nil) rethrows -> Step {
        var last: Step?
        for second in Swift.stride(from: range.lowerBound, through: range.upperBound, by: stride) {
            try before?(second)
            let step = step(TimeInterval(second), pid: pid)
            check?(step, second)
            last = step
        }
        return last!
    }

    /// The gateway is up for three hours and no message comes. It uses
    /// 20 percent of a core all the time, far more than was measured.
    func testAGatewayThatIsOnlyUpNeverWorks() throws {
        let sessions = try database()
        sessions.start("s1", at: at(-500))
        sessions.end("s1", at: at(-400))
        var cpu: TimeInterval = 0
        run(0...10_800, by: 5, before: { _ in
            cpu += 1
            self.census.rows = [self.gateway(cpu: cpu)]
        }, check: { step, second in
            XCTAssertEqual(step.evidence?.role, .engine, "\(second)")
            XCTAssertEqual(step.evidence?.level, .state, "\(second)")
            XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt), "\(second)")
        })
        XCTAssertEqual(step(10_801).evidence?.reported, StateReport(state: .idle, since: at(-400), observedAt: at(10_801), source: .openClawState, detail: nil))
    }

    /// A message comes in, and the run waits for a model for 400 seconds
    /// with no CPU use: work from its start to its end.
    func testATurnInsideTheGateway() throws {
        let sessions = try database()
        _ = try database("writer")
        census.rows = [gateway()]
        let open = run(0...9)
        XCTAssertEqual(open.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertTrue(open.watched.contains { $0.hasSuffix("/coordinator/agent/openclaw-agent.sqlite-wal") }, "A new run brings the next sample at once")

        sessions.start("s1", at: at(10))
        let began = step(10)
        XCTAssertEqual(began.evidence?.reported, StateReport(state: .working, since: at(10), observedAt: at(10), source: .openClawState, detail: "in a turn"))
        XCTAssertEqual(began.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertEqual(began.reading?.turn, AgentTurn(state: .working, since: at(10)))
        run(11...410) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }

        sessions.end("s1", at: at(411))
        let ended = step(411)
        XCTAssertEqual(ended.evidence?.reported, StateReport(state: .idle, since: at(411), observedAt: at(411), source: .openClawState, detail: nil))
        XCTAssertEqual(ended.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertEqual(ended.reading?.turn, AgentTurn(state: .idle))
        run(412...500) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
    }

    /// A run that was killed leaves its row. It holds while the row or
    /// the transcript is written, and for `runLimit` after the last write.
    func testARunThatNothingEnds() throws {
        let sessions = try database()
        census.rows = [gateway()]
        sessions.start("s1", at: at(0))
        let limit = Int(OpenClawSummary.runLimit)
        run(0...600, by: 5) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        sessions.write("s1", at: at(600))
        run(605...(600 + limit - 5), by: 5) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        let lapsed = run((600 + limit)...(600 + limit + 60), by: 5) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(lapsed.evidence?.reported?.state, .idle)
    }

    /// With no database, or with one that cannot be read, nothing is
    /// said. The gateway's own CPU use is still no sign of work, and a
    /// command below it that is busy is.
    func testAGatewayWhoseStateCannotBeRead() throws {
        var cpu: TimeInterval = 0
        var commandCPU: TimeInterval = 0
        let check: (Bool) throws -> Void = { broken in
            self.agentMemory = [:]
            try self.run(0...600, by: 5, before: { second in
                cpu += 1
                self.census.rows = [self.gateway(cpu: cpu)]
            }, check: { step, second in
                XCTAssertEqual(step.evidence?.level, .activity, "\(second) \(broken)")
                XCTAssertNil(step.evidence?.reported, "\(second) \(broken)")
                XCTAssertEqual(step.evidence?.cpuFraction ?? 0.2, 0.2, accuracy: 0.001, "\(second) \(broken)")
                XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second) \(broken)")
            })
            let building = try self.run(605...660, by: 5, before: { _ in
                cpu += 1
                commandCPU += 4
                self.census.rows = [
                    self.gateway(cpu: cpu),
                    .fixture(910, ppid: 900, start: self.processStart + 500, path: "/bin/zsh", args: ["zsh", "-c", "make"], cpu: commandCPU),
                ]
            })
            XCTAssertEqual(building.reading?.verdict, AgentVerdict(state: .working, confidence: .inferredStrong, reason: .runningCommand(1)), "\(broken)")
        }
        try check(false)
        let url = root.appendingPathComponent("agents/coordinator/agent/openclaw-agent.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is no database, and it is long enough to be read as one page of it".utf8).write(to: url)
        try check(true)
    }

    /// A chat in a terminal is a client of the gateway. It gets no state
    /// and is judged by the signs of activity, CPU use among them.
    func testASessionInATerminalIsJudgedByActivity() throws {
        let sessions = try database()
        sessions.start("s1", at: at(0))
        var cpu: TimeInterval = 0
        let chat = run(0...60, by: 5, pid: 700, before: { _ in
            cpu += 1
            self.census.rows = [.fixture(700, start: self.processStart, path: self.node, args: ["node", "/opt/homebrew/bin/openclaw", "tui"], cpu: cpu)]
        })
        XCTAssertEqual(chat.evidence?.level, .activity)
        XCTAssertNil(chat.evidence?.reported)
        XCTAssertEqual(chat.reading?.verdict, AgentVerdict(state: .working, confidence: .inferredWeak, reason: .cpuActivity))
    }
}

/// The record of 2026-10-08 (docs/research/12-openclaw.md): the gateway
/// took one turn of 3.5 seconds, was at rest for the 6 minutes after it,
/// and read as working to the end.
final class OpenClawRecordingTests: XCTestCase {
    private static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Recordings/synthetic-openclaw-gateway.jsonl")

    func testTheGatewayAtRestIsIdleForTheWholeRecord() throws {
        let recording = try LabFormat.recording(at: Self.url)
        XCTAssertEqual(recording.samples.count, 192)
        let live = recording.samples.compactMap { $0.verdicts.first?.state }
        XCTAssertEqual(live.filter { $0 == .working }.count, 178, "What the app said when it was recorded")
        XCTAssertEqual(live.last, .working)

        let steps = LabReplay.steps(of: recording)
        for step in steps {
            XCTAssertEqual(step.readings.map(\.agentID), ["openclaw"])
            XCTAssertEqual(step.readings.first?.verdict.state, .idle, "\(step.at.timeIntervalSince(steps[0].at))")
            XCTAssertFalse(step.decision.hold, "\(step.at.timeIntervalSince(steps[0].at))")
        }
        let score = LabReplay.score(recording)
        XCTAssertEqual(score.heldSeconds, 0)
        XCTAssertEqual(score.wronglyHeld, 0)
    }

    /// The same numbers for a process that is no gateway: the CPU rule
    /// holds as before, so the record does test it.
    func testTheSameUseCountsForASession() throws {
        var recording = try LabFormat.recording(at: Self.url)
        for index in recording.samples.indices {
            recording.samples[index].frame.agents = recording.samples[index].frame.agents.map { agent in
                var agent = agent
                agent.role = .session
                return agent
            }
        }
        let steps = LabReplay.steps(of: recording)
        XCTAssertEqual(steps.last?.readings.first?.verdict, AgentVerdict(state: .working, confidence: .inferredWeak, reason: .cpuActivity))
        XCTAssertEqual(steps.filter { $0.readings.first?.verdict.state == .working }.count, 178)
    }
}

/// OpenClaw is matched, and its gateway is judged by the state of its
/// sessions (docs/research/12-openclaw.md). No turn in progress was
/// measured, so the definition stays at activity and is not verified.
final class OpenClawCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow
    private let catalog = AgentCatalog.standard
    private let node = "/opt/homebrew/Cellar/node/26.8.1/bin/node"
    private let script = "/opt/homebrew/bin/openclaw"

    func testMatch() {
        let cases: [(name: String, args: [String], role: AgentRole?)] = [
            ("the TUI", ["node", script, "tui"], .session),
            ("one turn from the shell", ["node", script, "agent", "--message", "hi"], .session),
            ("no command", ["node", script], .session),
            ("the process with the title of the CLI", ["openclaw"], .session),
            ("the gateway in the foreground", ["node", script, "gateway", "--port", "18789"], .engine),
            ("the gateway, run", ["node", script, "gateway", "run"], .engine),
            ("the process with the title of the gateway", ["openclaw-gateway"], .engine),
            ("the state of the gateway", ["node", script, "gateway", "status"], .helper),
            ("the gateway service is restarted", ["node", script, "gateway", "restart"], .helper),
            ("the first setup", ["node", script, "onboard"], nil),
            ("the doctor", ["node", script, "doctor", "--fix"], nil),
            ("an update", ["node", script, "update"], nil),
            ("the plugins", ["node", script, "plugins", "list"], nil),
            ("the state", ["node", script, "status", "--all"], nil),
            ("a script of the user", ["node", "/Users/me/code/openclaw.js"], nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: node, args: c.args), userNames: [])
            XCTAssertEqual(match?.role, c.role, c.name)
            if c.role != nil { XCTAssertEqual(match?.definition.id, "openclaw", c.name) }
        }
        let definition = catalog.definitions.first { $0.id == AgentCatalog.openClawID }
        XCTAssertEqual(definition?.displayName, "OpenClaw")
        XCTAssertEqual(definition?.level, .activity)
        XCTAssertEqual(definition?.verified, false)
        XCTAssertEqual(definition?.processNames, ["openclaw"], "The name the old list knew, and no other")
    }

    /// The launcher and the process it starts are one agent, and so are
    /// the gateway and the process with its title. A command that the
    /// gateway runs is a child of it.
    func testInstances() {
        let rows: [Row] = [
            .fixture(700, path: node, args: ["node", script, "tui"]),
            .fixture(701, ppid: 700, path: node, args: ["openclaw"]),
            .fixture(900, path: node, args: ["node", script, "gateway", "--port", "18789"]),
            .fixture(901, ppid: 900, path: node, args: ["openclaw-gateway"]),
            .fixture(910, ppid: 901, path: "/bin/zsh", args: ["zsh", "-c", "sleep 400"]),
        ]
        let instances = catalog.instances(in: rows)
        XCTAssertEqual(instances.map(\.rootPID).sorted(), [700, 900])
        XCTAssertEqual(instances.first { $0.rootPID == 700 }?.rows.map(\.pid), [700, 701])
        XCTAssertEqual(instances.first { $0.rootPID == 900 }?.role, .engine)
        XCTAssertEqual(instances.first { $0.rootPID == 900 }?.rows.map(\.pid), [900, 901, 910])
    }
}
