import XCTest

private final class FakeCensus: ProcessCensusing {
    var rows: [ProcessInfoRow] = []
    func snapshot() -> [ProcessInfoRow]? { rows }
}

private final class FakeAssertions: PowerAssertionListing {
    var pids: Set<Int32> = []
    func assertingPIDs() -> Set<Int32> { pids }
}

private final class FakePower: PowerContextReading {
    func context() -> FrameContext { FrameContext() }
}

private final class FakeOpenFiles: OpenFileListing {
    func openFilePaths(of pid: Int32) -> [String]? { [] }
    func workingDirectory(of pid: Int32) -> String? { nil }
}

private struct FakeApps: AgentHostApps {
    var regular: Set<Int32>
    func isRegularApp(_ pid: Int32) -> Bool { regular.contains(pid) }
}

/// The process shapes of docs/research/09-claude-desktop.md, with the home
/// directory made generic.
private enum Shape {
    static let app = "/Applications/Claude.app/Contents"
    static let main = "\(app)/MacOS/Claude"
    static let helper = "\(app)/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"
    static let renderer = "\(app)/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"
    static let disclaimer = "\(app)/Helpers/disclaimer"
    static let code = "/Users/me/Library/Application Support/Claude/claude-code/2.1.293/8433d0d9cd0d/claude.app/Contents/MacOS/claude"
    static let codeArguments = [
        code, "--output-format", "stream-json", "--verbose", "--input-format", "stream-json", "--effort", "medium",
        "--permission-prompt-tool", "stdio", "--setting-sources=user,project,local", "--permission-mode", "default",
    ]
    static let terminalClaude = "/Users/me/.local/share/claude/versions/2.1.289"
}

final class ClaudeDesktopCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let catalog = AgentCatalog.standard

    func testMatch() {
        let cases: [(name: String, path: String, args: [String], id: String?, role: AgentRole?)] = [
            ("main", Shape.main, [Shape.main], "claude-desktop", .engine),
            ("main in another folder", "/Users/me/Applications/Claude.app/Contents/MacOS/Claude", ["Claude"], "claude-desktop", .engine),
            ("gpu", Shape.helper, [Shape.helper, "--type=gpu-process", "--user-data-dir=/Users/me/Library/Application Support/Claude"], "claude-desktop", .helper),
            ("node service", Shape.helper, [Shape.helper, "--type=utility", "--utility-sub-type=node.mojom.NodeService"], "claude-desktop", .helper),
            ("renderer", Shape.renderer, [Shape.renderer, "--type=renderer"], "claude-desktop", .helper),
            ("crash handler", "\(Shape.app)/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler", ["chrome_crashpad_handler", "--no-rate-limit"], "claude-desktop", .helper),
            ("disclaimer", Shape.disclaimer, [Shape.disclaimer, "--pgroup", "--"] + Shape.codeArguments, "claude-desktop", .helper),
            ("computer use helper", "\(Shape.app)/Helpers/app-cu-helper", ["app-cu-helper"], "claude-desktop", .helper),
            ("browser host", "\(Shape.app)/Helpers/chrome-native-host", ["chrome-native-host"], "claude-desktop", .helper),
            ("simulator app", "\(Shape.app)/Helpers/Claude iOS Sim.app/Contents/MacOS/Claude iOS Sim", ["Claude iOS Sim"], "claude-desktop", .helper),
            ("bundled server", "\(Shape.app)/Resources/app.asar.unpacked/resources/github-mcp/github-mcp-server", ["github-mcp-server", "stdio"], "claude-desktop", .helper),
            ("helper with the name of the command line tool", "\(Shape.app)/Helpers/claude", ["claude", "--stdio"], "claude-desktop", .helper),
            ("Code session", Shape.code, Shape.codeArguments, "claude-desktop", .session),
            ("Code session of a copy with other data", "/Users/me/Library/Application Support/Claude-3p/claude-code/2.1.300/0a1b2c3d4e5f/claude.app/Contents/MacOS/claude", ["claude", "--output-format", "stream-json"], "claude-desktop", .session),
            ("Claude Code in a terminal", Shape.terminalClaude, ["claude"], "claude", .session),
            ("server of a Code session", "/opt/homebrew/bin/node", ["npm exec some-server mcp"], nil, nil),
            ("another app with a binary named Claude", "/Applications/Other.app/Contents/MacOS/Claude", ["Claude"], nil, nil),
            ("a helper of another app named like ours", "/Applications/Other.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper", ["Claude Helper"], nil, nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: c.path, args: c.args), userNames: [])
            XCTAssertEqual(match?.definition.id, c.id, c.name)
            XCTAssertEqual(match?.role, c.role, c.name)
        }
        let definition = catalog.definitions.first { $0.id == AgentCatalog.claudeDesktopID }
        XCTAssertEqual(definition?.displayName, "Claude")
        XCTAssertEqual(definition?.kind, .desktop)
        XCTAssertEqual(definition?.level, .state)
        XCTAssertEqual(definition?.verified, true)
        XCTAssertEqual(catalog.definitions.first { $0.id == "claude" }?.displayName, "Claude Code")
        XCTAssertNotNil(AgentLogo.markByAgentID[AgentCatalog.claudeDesktopID])
    }

    private var snapshot: [Row] {
        [
            .fixture(500, path: Shape.main, args: [Shape.main]),
            .fixture(510, ppid: 500, path: Shape.renderer, args: [Shape.renderer, "--type=renderer"]),
            .fixture(511, ppid: 500, path: Shape.helper, args: [Shape.helper, "--type=utility", "--utility-sub-type=node.mojom.NodeService"]),
            .fixture(520, ppid: 500, path: "/opt/homebrew/bin/node", args: ["node", "/Users/me/servers/files.js"]),
            .fixture(600, ppid: 500, path: Shape.disclaimer, args: [Shape.disclaimer, "--pgroup", "--"] + Shape.codeArguments),
            .fixture(620, ppid: 600, path: Shape.code, args: Shape.codeArguments),
            .fixture(630, ppid: 620, path: "/opt/homebrew/bin/node", args: ["npm exec some-server mcp"]),
            .fixture(700, ppid: 500, path: Shape.disclaimer, args: [Shape.disclaimer, "--pgroup", "--"] + Shape.codeArguments),
            .fixture(720, ppid: 700, path: Shape.code, args: Shape.codeArguments),
            .fixture(900, path: "/bin/zsh", args: ["-zsh"], tty: 5),
            .fixture(910, ppid: 900, path: Shape.terminalClaude, args: ["claude"], tty: 5),
        ]
    }

    func testTheAppAndEachCodeSessionAreInstancesAndNothingIsCountedTwice() {
        let instances = catalog.instances(in: snapshot)
        XCTAssertEqual(instances.map(\.definitionID), ["claude-desktop", "claude-desktop", "claude-desktop", "claude"])
        XCTAssertEqual(instances.map(\.rootPID), [500, 620, 720, 910])
        XCTAssertEqual(instances.map(\.role), [.engine, .session, .session, .session])
        XCTAssertEqual(instances[0].rows.map(\.pid), [500, 510, 511, 520, 600, 700], "The app ends where a Code session starts")
        XCTAssertEqual(instances[1].rows.map(\.pid), [620, 630])
        XCTAssertEqual(instances[2].rows.map(\.pid), [720])
        let all = instances.flatMap { $0.rows.map(\.pid) }
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testAHookOfACodeSessionLandsOnThatSession() {
        let hook = Row.fixture(640, ppid: 620, path: "/bin/sh", args: ["sh", "-c", "CaffeinagentHook claude Stop v=1"])
        let rows = snapshot
        let chain = [hook, rows[5], rows[4], rows[0]]
        XCTAssertEqual(HookCommand.agentProcess(in: chain, hookAgent: "claude")?.pid, 620)
        XCTAssertNil(HookCommand.agentProcess(in: chain, hookAgent: "codex"))
        XCTAssertEqual(HookEvents.hookAgent(forDefinition: AgentCatalog.claudeDesktopID), "claude")
        XCTAssertEqual(HookCatalog.entry(forDefinition: AgentCatalog.claudeDesktopID)?.id, "claude")
    }

    func testAClickOnACodeSessionGoesToTheApp() {
        let table = AgentHostTable(rows: snapshot)
        let apps = FakeApps(regular: [500])
        XCTAssertEqual(AgentHostResolver.resolve(pid: 620, kind: .desktop, table: table, apps: apps), AgentHost(appPid: 500))
        XCTAssertEqual(AgentHostResolver.resolve(pid: 500, kind: .desktop, table: table, apps: apps), AgentHost(appPid: 500))
        XCTAssertEqual(
            AgentHostReveal.way(bundleURL: URL(fileURLWithPath: "/Applications/Claude.app"), executableURL: URL(fileURLWithPath: Shape.main)),
            .open(bundle: URL(fileURLWithPath: "/Applications/Claude.app"))
        )
    }

    /// The keys of a real file, with made-up values.
    func testTheSessionFileOfACodeSession() throws {
        let text = #"{"pid":620,"sessionId":"7b0c1f0e-1111-4222-8333-444455556666","cwd":"/Users/me/code/site","startedAt":1791470707783,"procStart":"x","version":"2.1.293","peerProtocol":1,"kind":"interactive","entrypoint":"claude-desktop","hostSessionId":"local_00000000-0000-4000-8000-000000000000","status":"waiting","waitingFor":"permission prompt","updatedAt":1791470710967,"statusUpdatedAt":1791470710967}"#
        let state = try XCTUnwrap(ClaudeSessionStateReader.parse(Data(text.utf8), now: Date(timeIntervalSince1970: 1_791_470_720)))
        XCTAssertEqual(state.entrypoint, AgentCatalog.claudeDesktopEntrypoint)
        XCTAssertEqual(state.state, .waitingForUser)
        XCTAssertEqual(state.kind, .interactive)
        XCTAssertEqual(state.statusUpdatedAt, Date(timeIntervalSince1970: 1_791_470_710.967))
        let terminal = try XCTUnwrap(ClaudeSessionStateReader.parse(Data(#"{"pid":910,"entrypoint":"cli","status":"idle"}"#.utf8), now: Date()))
        XCTAssertEqual(terminal.entrypoint, "cli")
        XCTAssertNil(ClaudeSessionStateReader.parse(Data(#"{"pid":910,"status":"busy"}"#.utf8), now: Date())?.entrypoint)
    }
}

/// The whole way for the Claude app: files and processes in, the verdict,
/// the hold and the notifications out.
final class ClaudeDesktopTimelineTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }

    private var root: URL!
    private var census: FakeCensus!
    private var assertions: FakeAssertions!
    private var sources: EvidenceCollector.Sources!
    private var collector: EvidenceCollector!
    private var seconds: TimeInterval = 0
    private var agentMemory: [ProcessIdentity: AgentMemory] = [:]
    private var policyMemory = PolicyMemory()
    private var reducer = AgentNoticeReducer()
    private var told: [(at: TimeInterval, notice: AgentNotice)] = []
    private let settings = DetectionSettings()

    struct Step {
        var sample: EvidenceSample
        var readings: [AgentReading]
        var decision: HoldDecision

        func evidence(_ pid: Int32) -> AgentEvidence? { sample.frame.agents.first { $0.pid == pid } }
        func reading(_ pid: Int32) -> AgentReading? { readings.first { $0.identity.pid == pid } }
        var pids: [Int32] { sample.frame.agents.map(\.pid) }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-desktop-\(UUID().uuidString)")
        for name in ["sessions", "jobs", "projects", "hooks"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        census = FakeCensus()
        assertions = FakeAssertions()
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: FakePower(), openFiles: FakeOpenFiles())
        sources.claudeSessions = ClaudeSessionStateReader(sessionsDirectory: root.appendingPathComponent("sessions"))
        sources.claudeJobs = ClaudeJobStateReader(jobsDirectory: root.appendingPathComponent("jobs"))
        sources.claudeProjects = root.appendingPathComponent("projects")
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        self.sources = sources
        collector = EvidenceCollector(sources: sources)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    /// The app with no Code session. `cpu` is what its renderer used.
    private func app(cpu: TimeInterval = 0) -> [Row] {
        [
            .fixture(500, start: processStart, path: Shape.main, args: [Shape.main], cpu: cpu / 4),
            .fixture(510, ppid: 500, start: processStart, path: Shape.renderer, args: [Shape.renderer, "--type=renderer"], cpu: cpu),
            .fixture(511, ppid: 500, start: processStart, path: Shape.helper, args: [Shape.helper, "--type=utility", "--utility-sub-type=node.mojom.NodeService"]),
        ]
    }

    /// One session of the Code tab, with a server below it.
    private func code(_ pid: Int32 = 620) -> [Row] {
        [
            .fixture(pid - 20, ppid: 500, start: processStart + 60, path: Shape.disclaimer, args: [Shape.disclaimer, "--pgroup", "--"] + Shape.codeArguments),
            .fixture(pid, ppid: pid - 20, start: processStart + 60, path: Shape.code, args: Shape.codeArguments),
            .fixture(pid + 10, ppid: pid, start: processStart + 61, path: "/opt/homebrew/bin/node", args: ["npm exec some-server mcp"]),
        ]
    }

    private func terminalClaude() -> [Row] {
        [.fixture(900, path: "/bin/zsh", args: ["-zsh"], tty: 5), .fixture(910, ppid: 900, start: processStart, path: Shape.terminalClaude, args: ["claude"], tty: 5)]
    }

    private func writeSession(_ pid: Int32, _ status: String, since seconds: TimeInterval, entrypoint: String = "claude-desktop") throws {
        let milliseconds = Int((at(seconds).timeIntervalSince1970 * 1000).rounded())
        let text = #"{"pid":\#(pid),"kind":"interactive","entrypoint":"\#(entrypoint)","status":"\#(status)","statusUpdatedAt":\#(milliseconds)}"#
        try Data(text.utf8).write(to: root.appendingPathComponent("sessions/\(pid).json"), options: .atomic)
    }

    @discardableResult
    private func step(_ seconds: TimeInterval) -> Step {
        self.seconds = seconds
        let sample = collector.collect()
        let (readings, memory) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
        agentMemory = memory
        let (decision, policy) = HoldPolicy.decide(
            readings: readings, memory: policyMemory, mode: .agentWorking, enabled: true, safety: nil,
            settings: settings, context: sample.frame.context, now: sample.frame.at
        )
        policyMemory = policy
        let notices = reducer.update(AgentNoticeInput(readings: readings, settings: AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: false)), now: sample.frame.at)
        told += notices.map { (seconds, $0) }
        return Step(sample: sample, readings: readings, decision: decision)
    }

    @discardableResult
    private func run(_ range: ClosedRange<Int>, by stride: Int = 1, check: ((Step, Int) -> Void)? = nil) -> Step {
        var last: Step?
        for second in Swift.stride(from: range.lowerBound, through: range.upperBound, by: stride) {
            let step = step(TimeInterval(second))
            check?(step, second)
            last = step
        }
        return last!
    }

    func testATurnInTheCodeTabNextToAClaudeCodeInATerminal() throws {
        census.rows = app() + code() + terminalClaude()
        try writeSession(620, "idle", since: -300)
        try writeSession(910, "idle", since: -300, entrypoint: "cli")
        let idle = run(0...9)
        XCTAssertEqual(idle.sample.frame.agents.map(\.agentID), ["claude-desktop", "claude"], "One line for the app, one for the terminal")
        XCTAssertEqual(idle.pids, [620, 910], "The session stands for the app, and the app has no line of its own")
        let session = try XCTUnwrap(idle.evidence(620))
        XCTAssertEqual(session.displayName, "Claude")
        XCTAssertEqual(session.kind, .desktop)
        XCTAssertEqual(session.role, .session)
        XCTAssertEqual(session.level, .state)
        XCTAssertEqual(session.reported?.source, .claudeSessionFile)
        XCTAssertTrue(session.hasLiveSession)
        XCTAssertEqual(session.childCommands, 1, "Its server")
        XCTAssertEqual(idle.evidence(910)?.displayName, "Claude Code")
        XCTAssertEqual(idle.reading(620)?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertFalse(idle.decision.hold)

        // The prompt. The app takes its own assertion for the turn.
        try writeSession(620, "busy", since: 10)
        assertions.pids = [500]
        run(10...69) { step, second in
            XCTAssertEqual(step.pids, [620, 910], "\(second)")
            XCTAssertEqual(step.reading(620)?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy), "\(second)")
            XCTAssertEqual(step.reading(620)?.turn, AgentTurn(state: .working, since: self.at(10)), "\(second)")
            XCTAssertEqual(step.reading(910)?.verdict.state, .idle, "\(second)")
            XCTAssertEqual(step.decision.perAgent.filter { $0.cause == .working }.count, 1, "\(second)")
            XCTAssertTrue(step.decision.hold, "\(second)")
        }

        // The end. The app keeps its assertion for 30 seconds more.
        try writeSession(620, "idle", since: 70)
        let ended = step(70)
        XCTAssertEqual(ended.reading(620)?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertEqual(ended.decision.perAgent.first { $0.reading.identity.pid == 620 }?.cause, .finishedRecently)
        run(71...100) { step, second in XCTAssertEqual(step.pids, [620, 910], "\(second)") }
        assertions.pids = []
        run(101...300) { step, second in
            XCTAssertEqual(step.pids, [620, 910], "\(second)")
            XCTAssertEqual(step.decision.hold, second < 69 + 120, "\(second)")
        }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
        XCTAssertEqual(told.first?.notice.sessions.map(\.identity.pid), [620])
        XCTAssertEqual(told.first?.notice.sessions.first?.displayName, "Claude")
        XCTAssertEqual(told.first?.notice.sessions.first?.workedFor ?? 0, 60, accuracy: 0.5)
    }

    func testAnApprovalInTheCodeTabIsAWait() throws {
        census.rows = app() + code()
        try writeSession(620, "busy", since: 0)
        XCTAssertEqual(run(0...5).reading(620)?.verdict.state, .working)
        try writeSession(620, "waiting", since: 6)
        run(6...60) { step, second in
            XCTAssertEqual(step.reading(620)?.verdict, AgentVerdict(state: .waitingForUser, confidence: .reported, reason: .asksPermission), "\(second)")
            XCTAssertEqual(step.reading(620)?.turn, AgentTurn(state: .waitingForUser), "\(second)")
        }
        XCTAssertEqual(told.map(\.notice.kind), [.waiting])
        XCTAssertEqual(told.first?.notice.sessions.map(\.identity.pid), [620])
        try writeSession(620, "busy", since: 61)
        XCTAssertEqual(step(61).reading(620)?.verdict.state, .working)
    }

    /// A chat answer is made on a server. The renderer that draws it uses
    /// the CPU, and so does a user who scrolls.
    func testTheAppOpenForAnHourWithABusyWindowIsIdle() {
        var cpu: TimeInterval = 0
        census.rows = app()
        run(0...3600, by: 5) { step, second in
            cpu += 2
            self.census.rows = self.app(cpu: cpu)
            XCTAssertEqual(step.pids, [500], "\(second)")
            XCTAssertEqual(step.evidence(500)?.subtreeCPUSeconds, 0, "\(second)")
            XCTAssertEqual(step.reading(500)?.verdict.state, .idle, "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
        let last = step(3605)
        XCTAssertEqual(last.evidence(500)?.agentID, "claude-desktop")
        XCTAssertEqual(last.evidence(500)?.displayName, "Claude")
        XCTAssertEqual(last.evidence(500)?.role, .engine)
        XCTAssertEqual(last.evidence(500)?.level, .activity, "The app itself states nothing")
        XCTAssertFalse(last.evidence(500)?.hasLiveSession ?? true)
        XCTAssertEqual(last.reading(500)?.verdict.reason, .noActivity(minutes: 60))
        XCTAssertTrue(told.isEmpty)
    }

    func testAnIdleCodeSessionForAnHourIsIdle() throws {
        try writeSession(620, "idle", since: -60)
        var cpu: TimeInterval = 0
        census.rows = app() + code()
        run(0...3600, by: 5) { step, second in
            cpu += 2
            self.census.rows = self.app(cpu: cpu) + self.code()
            XCTAssertEqual(step.pids, [620], "\(second)")
            XCTAssertEqual(step.reading(620)?.verdict.state, .idle, "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
    }

    func testACodeSessionThatEndsIsGoneAndTheAppStays() throws {
        census.rows = app() + code() + code(720)
        try writeSession(620, "busy", since: 0)
        try writeSession(720, "idle", since: -60)
        let two = run(0...5)
        XCTAssertEqual(two.pids, [620, 720])
        XCTAssertEqual(two.readings.map(\.verdict.state), [.working, .idle])
        XCTAssertTrue(two.decision.hold)

        census.rows = app() + code(720)
        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions/620.json"))
        let one = step(6)
        XCTAssertEqual(one.pids, [720])
        XCTAssertFalse(one.decision.hold, "The session that worked is gone")

        census.rows = app()
        try FileManager.default.removeItem(at: root.appendingPathComponent("sessions/720.json"))
        let none = step(7)
        XCTAssertEqual(none.pids, [500], "The app is open with no Code session")
        XCTAssertEqual(none.reading(500)?.verdict.state, .idle)

        census.rows = []
        XCTAssertEqual(step(8).decision.headline, .noAgents)
    }

    /// The process is there before its session file: it starts up, or it
    /// is the app that asks its Claude Code for a version.
    func testACodeProcessWithNoSessionFileIsNoSession() throws {
        census.rows = app() + code()
        XCTAssertEqual(run(0...3).pids, [500])
        try writeSession(620, "idle", since: 4)
        XCTAssertEqual(step(4).pids, [620])
    }

    /// Measured on 2026-10-08: the app took its assertion for 5 minutes at
    /// a time with no turn and no task, and read as working for hours.
    func testTheAssertionOfTheAppAloneIsNoWork() {
        census.rows = app()
        run(0...5)
        assertions.pids = [500]
        let held = run(6...306) { step, second in
            XCTAssertEqual(step.pids, [500], "\(second)")
            XCTAssertTrue(step.evidence(500)?.ownsSleepAssertion ?? false, "It is recorded: \(second)")
            XCTAssertEqual(step.reading(500)?.verdict.state, .idle, "\(second)")
            XCTAssertNil(step.reading(500)?.turn, "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
        XCTAssertEqual(held.reading(500)?.verdict, AgentVerdict(state: .idle, confidence: .inferredWeak, reason: .noActivity(minutes: 5)))
        assertions.pids = []
        XCTAssertEqual(step(307).reading(500)?.verdict.state, .idle)
        XCTAssertTrue(told.isEmpty)
    }

    func testTheAssertionOfTheAppWithAnIdleCodeSessionIsIdle() throws {
        census.rows = app() + code()
        try writeSession(620, "idle", since: -300)
        run(0...5)
        assertions.pids = [500]
        run(6...306) { step, second in
            XCTAssertEqual(step.pids, [620], "The app has no line of its own: \(second)")
            XCTAssertEqual(step.reading(620)?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt), "\(second)")
            XCTAssertEqual(step.reading(620)?.turn, AgentTurn(state: .idle), "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
        XCTAssertTrue(told.isEmpty)
    }

    /// The session file decides, with the assertion and without it.
    func testTheAssertionOfTheAppWithACodeSessionInATurnIsWork() throws {
        census.rows = app() + code()
        try writeSession(620, "idle", since: -300)
        assertions.pids = [500]
        XCTAssertEqual(run(0...5).reading(620)?.verdict.state, .idle)
        try writeSession(620, "busy", since: 6)
        run(6...120) { step, second in
            if second == 60 { self.assertions.pids = [] }
            XCTAssertEqual(step.pids, [620], "\(second)")
            XCTAssertEqual(step.reading(620)?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy), "\(second)")
            XCTAssertEqual(step.reading(620)?.turn, AgentTurn(state: .working, since: self.at(6)), "\(second)")
            XCTAssertTrue(step.decision.hold, "\(second)")
        }
    }

    /// 5 minutes held, 3 minutes not, for an hour and a half. The time
    /// between two holds is shorter than the release time after a sign of
    /// work, so one hold that counted would never end.
    func testAnAssertionThatComesAndGoesLeavesTheIdleAppIdle() throws {
        try writeSession(620, "idle", since: -300)
        var clock = StateClock()
        for rows in [app(), app() + code()] {
            census.rows = rows
            let pid: Int32 = rows.count > 3 ? 620 : 500
            let from = pid == 500 ? 0 : 5405
            run(from...(from + 5400), by: 5) { step, second in
                self.assertions.pids = (second - from) % 480 < 300 ? [500] : []
                XCTAssertEqual(step.pids, [pid], "\(second)")
                XCTAssertEqual(step.reading(pid)?.verdict.state, .idle, "\(second)")
                XCTAssertNotEqual(step.reading(pid)?.turn?.state, .working, "\(second)")
                XCTAssertFalse(step.decision.hold, "\(second)")
                clock = clock.updated(with: step.readings, now: step.sample.frame.at)
                XCTAssertEqual(clock.entries[step.readings[0].identity]?.state, .idle, "\(second)")
                XCTAssertNil(clock.before(step.readings[0].identity), "It never left idle: \(second)")
            }
        }
        XCTAssertTrue(told.isEmpty)
    }

    /// The state clock of the menu starts again at each change of state,
    /// so the time of a turn does not reach over an idle stretch.
    func testWorkingSinceStartsAgainAfterAnIdleStretch() throws {
        census.rows = app() + code()
        var clock = StateClock()
        func tick(_ second: TimeInterval) -> Step {
            let step = step(second)
            clock = clock.updated(with: step.readings, now: step.sample.frame.at)
            return step
        }
        try writeSession(620, "busy", since: 0)
        (0...60).forEach { _ = tick(TimeInterval($0)) }
        let identity = try XCTUnwrap(tick(61).reading(620)?.identity)
        XCTAssertEqual(clock.since(identity), at(0))
        try writeSession(620, "idle", since: 62)
        assertions.pids = [500]
        (62...600).forEach { _ = tick(TimeInterval($0)) }
        XCTAssertEqual(clock.entries[identity]?.state, .idle)
        XCTAssertEqual(clock.since(identity), at(62))
        try writeSession(620, "busy", since: 601)
        let again = tick(601)
        XCTAssertEqual(again.reading(620)?.turn, AgentTurn(state: .working, since: at(601)))
        XCTAssertEqual(clock.since(identity), at(601))
        XCTAssertEqual(clock.before(identity), .idle)
    }

    func testTheAppHasItsOwnLineNextToACodeSessionOnceItWorksItself() throws {
        func rows(cpu: TimeInterval) -> [Row] {
            app() + code() + [.fixture(520, ppid: 500, start: processStart, path: "/opt/homebrew/bin/node", args: ["node", "/Users/me/servers/files.js"], cpu: cpu)]
        }
        census.rows = rows(cpu: 0)
        try writeSession(620, "idle", since: -60)
        assertions.pids = [500]
        XCTAssertEqual(run(0...20).pids, [620], "The assertion gives the app no line")
        var cpu: TimeInterval = 0
        let both = run(21...40) { _, _ in
            cpu += 0.5
            self.census.rows = rows(cpu: cpu)
        }
        XCTAssertEqual(both.pids, [620, 500])
        XCTAssertEqual(both.readings.map(\.verdict.state), [.idle, .working])
        XCTAssertEqual(both.reading(500)?.verdict.reason, .runningCommand(1))
        XCTAssertEqual(Set(both.sample.frame.agents.map(\.agentID)), ["claude-desktop"], "One group in the panel")
    }

    /// A server of the chat that runs a long tool call on this Mac.
    func testABusyServerOfTheChatIsWork() {
        func rows(cpu: TimeInterval) -> [Row] {
            app() + [.fixture(520, ppid: 500, start: processStart, path: "/opt/homebrew/bin/node", args: ["node", "/Users/me/servers/files.js"], cpu: cpu)]
        }
        census.rows = rows(cpu: 0)
        let quiet = run(0...20)
        XCTAssertEqual(quiet.evidence(500)?.childCommands, 1)
        XCTAssertEqual(quiet.reading(500)?.verdict.state, .idle)
        var cpu: TimeInterval = 0
        let busy = run(21...40) { _, _ in
            cpu += 0.5
            self.census.rows = rows(cpu: cpu)
        }
        XCTAssertEqual(busy.reading(500)?.verdict, AgentVerdict(state: .working, confidence: .inferredStrong, reason: .runningCommand(1)))
    }

    /// The app could start a Claude Code that is not the one it keeps.
    /// The session file still names the app.
    func testASessionThatNamesTheAppAsItsEntryPointIsALineOfTheApp() throws {
        let session = Row.fixture(620, ppid: 600, start: processStart + 60, path: Shape.terminalClaude, args: ["claude", "--output-format", "stream-json"])
        census.rows = app() + [.fixture(600, ppid: 500, start: processStart + 60, path: Shape.disclaimer, args: [Shape.disclaimer, "--pgroup", "--"]), session] + terminalClaude()
        try writeSession(620, "busy", since: 0)
        try writeSession(910, "busy", since: 0, entrypoint: "cli")
        let first = step(0)
        XCTAssertEqual(first.sample.frame.agents.map(\.agentID), ["claude-desktop", "claude"])
        XCTAssertEqual(first.evidence(620)?.displayName, "Claude")
        XCTAssertEqual(first.evidence(620)?.kind, .desktop)
        // Read in the middle of a write.
        try Data("{".utf8).write(to: root.appendingPathComponent("sessions/620.json"))
        let cut = step(1)
        XCTAssertEqual(cut.sample.frame.agents.map(\.agentID), ["claude-desktop", "claude"])
        XCTAssertEqual(cut.reading(620)?.verdict.state, .working, "The last state stands for a short time")
    }

    func testTheHookStateOfACodeSessionReachesItsLine() throws {
        sources.hookDirectory = root.appendingPathComponent("hooks")
        collector = EvidenceCollector(sources: sources)
        census.rows = app() + code()
        try writeSession(620, "busy", since: 0)
        var file = HookStateFile(agent: "claude", pid: 620, start: processStart + 60)
        file.apply(.set(.waitingForUser), session: "a", event: "Notification", at: at(1))
        try JSONEncoder().encode(file).write(to: root.appendingPathComponent("hooks/\(HookStateFile.fileName(agent: "claude", pid: 620))"))
        let step = step(2)
        XCTAssertEqual(step.pids, [620])
        XCTAssertEqual(step.evidence(620)?.hookState, .waitingForUser)
        XCTAssertEqual(step.reading(620)?.verdict.state, .waitingForUser)
    }
}
