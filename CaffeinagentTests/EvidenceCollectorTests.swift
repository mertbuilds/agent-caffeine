import XCTest

private final class FakeCensus: ProcessCensusing {
    var rows: [ProcessInfoRow] = []
    var unreadable = false
    func snapshot() -> [ProcessInfoRow]? { unreadable ? nil : rows }
}

private final class FakeAssertions: PowerAssertionListing {
    var pids: Set<Int32> = []
    func assertingPIDs() -> Set<Int32> { pids }
}

private final class FakePower: PowerContextReading {
    var value = FrameContext()
    func context() -> FrameContext { value }
}

private final class FakeOpenFiles: OpenFileListing {
    var files: [Int32: [String]] = [:]
    var directories: [Int32: String] = [:]
    func openFilePaths(of pid: Int32) -> [String]? { files[pid] }
    func workingDirectory(of pid: Int32) -> String? { directories[pid] }
}

final class EvidenceCollectorTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let claudeBinary = "/Users/me/.local/share/claude/versions/2.1.289"
    private let codexDesktopBinary = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    /// Files get the real time of the test run, so the clock starts there.
    private let base = Date()
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }

    private var root: URL!
    private var census: FakeCensus!
    private var assertions: FakeAssertions!
    private var power: FakePower!
    private var openFiles: FakeOpenFiles!
    private var seconds: TimeInterval = 0
    private var collector: EvidenceCollector!
    private var sources: EvidenceCollector.Sources!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("collector-\(UUID().uuidString)")
        for name in ["sessions", "jobs", "projects", "codex", "store"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        census = FakeCensus()
        assertions = FakeAssertions()
        power = FakePower()
        openFiles = FakeOpenFiles()
        seconds = 0
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: power, openFiles: openFiles)
        sources.claudeSessions = ClaudeSessionStateReader(sessionsDirectory: root.appendingPathComponent("sessions"))
        sources.claudeJobs = ClaudeJobStateReader(jobsDirectory: root.appendingPathComponent("jobs"))
        sources.claudeProjects = root.appendingPathComponent("projects")
        sources.codexRollouts = CodexRolloutReader(sessionsDirectory: root.appendingPathComponent("codex"))
        sources.fileActivityTargets = ["opencode": .paths([root.appendingPathComponent("store/opencode.db-wal")])]
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        self.sources = sources
        collector = EvidenceCollector(sources: sources)
    }

    /// A collector that also reads hook states and Claude Code's settings.
    private func collectWithHooks() -> URL {
        let hooks = root.appendingPathComponent("hooks")
        sources.hookDirectory = hooks
        sources.claudeSettings = root.appendingPathComponent("claude-settings.json")
        collector = EvidenceCollector(sources: sources)
        return hooks
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private func sample(at seconds: TimeInterval) -> EvidenceSample {
        self.seconds = seconds
        return collector.collect()
    }

    private func claude(_ pid: Int32, ppid: Int32 = 1, args: [String] = ["claude", "--dangerously-skip-permissions"], cpu: TimeInterval = 0, energy: UInt64? = nil, writes: UInt64? = nil) -> Row {
        .fixture(pid, ppid: ppid, start: processStart, path: claudeBinary, args: args, cpu: cpu, energy: energy, writes: writes)
    }

    @discardableResult
    private func write(_ text: String, to path: String, modified: Date? = nil) throws -> String {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url.path
    }

    @discardableResult
    private func writeSession(_ pid: Int32, status: String, extra: String = "") throws -> String {
        try write(#"{"pid":\#(pid),"kind":"interactive","status":"\#(status)","statusUpdatedAt":1791199000000\#(extra)}"#, to: "sessions/\(pid).json")
    }

    private func rollout(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    private func meta(cwd: String) -> String {
        #"{"timestamp":"2026-10-05T12:00:00.000Z","type":"session_meta","payload":{"id":"01a10000-aaaa-7000-8000-00000000c78f","cwd":"\#(cwd)"}}"#
    }

    private let turnStarted = #"{"timestamp":"2026-10-05T12:00:02.500Z","type":"event_msg","payload":{"type":"task_started","turn_id":"a","started_at":1791201602}}"#
    private let turnComplete = #"{"timestamp":"2026-10-05T12:01:00.500Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"a","completed_at":1791201660}}"#

    // MARK: Claude Code

    func testClaudeSessionsReportTheirState() throws {
        census.rows = [.fixture(10, path: "/bin/zsh", args: ["-zsh"]), claude(100, ppid: 10), claude(200, ppid: 10)]
        let busy = try writeSession(100, status: "busy")
        let idle = try writeSession(200, status: "idle")
        power.value = FrameContext(onBattery: true, batteryPercent: 64, lidClosed: true, thermalState: ProcessInfo.ThermalState.fair.rawValue)

        let sample = sample(at: 0)
        XCTAssertEqual(sample.frame.at, at(0))
        XCTAssertEqual(sample.frame.context, power.value)
        XCTAssertEqual(sample.frame.agents.map(\.pid), [100, 200])
        XCTAssertEqual(sample.frame.agents.map(\.reported?.state), [.working, .idle])
        XCTAssertEqual(sample.frame.agents.map(\.reported?.source), [.claudeSessionFile, .claudeSessionFile])
        XCTAssertEqual(sample.frame.agents.map(\.reported?.observedAt), [at(0), at(0)])
        let first = try XCTUnwrap(sample.frame.agents.first)
        XCTAssertEqual(first.agentID, "claude")
        XCTAssertEqual(first.level, .state)
        XCTAssertEqual(first.role, .session)
        XCTAssertEqual(first.startTime, processStart)
        XCTAssertEqual(first.sampleInterval, 0, "The first sample of a process carries no CPU number")
        XCTAssertNil(first.fileActivityAt)
        XCTAssertEqual(sample.watchedFiles, [busy, idle])
        XCTAssertEqual(sample.roots, [ProcessIdentity(pid: 100, startTime: processStart), ProcessIdentity(pid: 200, startTime: processStart)])
    }

    func testRemoteAccessComesFromTheHook() {
        XCTAssertFalse(sample(at: 0).frame.context.remoteAccessDetected)
        collector.remoteAccessProbe = { true }
        XCTAssertTrue(sample(at: 2).frame.context.remoteAccessDetected)
    }

    func testRemoteAccessFromClaudeRemoteControl() throws {
        _ = collectWithHooks()
        census.rows = [claude(100)]
        XCTAssertFalse(sample(at: 0).frame.context.remoteAccessDetected)
        census.rows = [claude(100), claude(200, args: ["claude", "remote-control"])]
        XCTAssertTrue(sample(at: 2).frame.context.remoteAccessDetected)
        census.rows = [claude(100)]
        try Data(#"{"remoteControlAtStartup": true}"#.utf8).write(to: root.appendingPathComponent("claude-settings.json"))
        XCTAssertTrue(sample(at: 4).frame.context.remoteAccessDetected)
        census.rows = []
        XCTAssertFalse(sample(at: 6).frame.context.remoteAccessDetected, "No session is open")
    }

    func testHookStateReachesTheInstanceOfItsProcess() throws {
        let hooks = collectWithHooks()
        census.rows = [claude(100), claude(200)]
        var file = HookStateFile(agent: "claude", pid: 100, start: processStart)
        file.apply(.set(.waitingForUser), session: "a", event: "Notification", at: at(1))
        let path = hooks.appendingPathComponent(HookStateFile.fileName(agent: "claude", pid: 100))
        try JSONEncoder().encode(file).write(to: path)

        let sample = sample(at: 2)
        let first = try XCTUnwrap(sample.frame.agents.first { $0.pid == 100 })
        XCTAssertEqual(first.hookState, .waitingForUser)
        XCTAssertEqual(try XCTUnwrap(first.hookStateAt).timeIntervalSince(at(1)), 0, accuracy: 0.001)
        XCTAssertNil(sample.frame.agents.first { $0.pid == 200 }?.hookState)
        XCTAssertTrue(sample.watchedFiles.contains(hooks.path), "A new state file is a new entry in the folder")
        XCTAssertTrue(sample.watchedFiles.contains(path.path))
    }

    func testHookFileOfAnotherAgentOrAnotherProcessIsNotUsed() throws {
        let hooks = collectWithHooks()
        census.rows = [claude(100)]
        var wrongAgent = HookStateFile(agent: "codex", pid: 100, start: processStart)
        wrongAgent.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: at(1))
        try JSONEncoder().encode(wrongAgent).write(to: hooks.appendingPathComponent("codex-100.json"))
        XCTAssertNil(sample(at: 2).frame.agents.first?.hookState)

        // The pid was used again by a process that started later.
        var reused = HookStateFile(agent: "claude", pid: 100, start: processStart - 50)
        reused.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: at(1))
        let path = hooks.appendingPathComponent("claude-100.json")
        try JSONEncoder().encode(reused).write(to: path)
        XCTAssertNil(sample(at: 4).frame.agents.first?.hookState)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "A young file is kept")
    }

    func testHookFileOfADeadProcessIsRemovedOnceItIsOld() throws {
        let hooks = collectWithHooks()
        var file = HookStateFile(agent: "claude", pid: 100, start: processStart)
        file.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: at(0))
        let path = hooks.appendingPathComponent("claude-100.json")
        try JSONEncoder().encode(file).write(to: path)
        census.rows = []
        _ = sample(at: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        _ = sample(at: HookStateReader.removalAge + 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    /// The daemon family as it runs on a Mac: argv[0] is the whole title.
    func testWarmSpareIsLeftOutAndClaimedSpareIsASession() throws {
        func spare(_ pid: Int32, ppid: Int32) -> Row { claude(pid, ppid: ppid, args: ["claude bg-spare", "--bg-spare", "/tmp/x.claim.sock"]) }
        func host(_ pid: Int32) -> Row { claude(pid, ppid: 20, args: ["claude bg-pty-host", "--bg-pty-host", "/tmp/x.pty.sock"]) }
        census.rows = [
            claude(10), claude(20, ppid: 10, args: ["claude", "daemon", "run"]),
            host(30), spare(31, ppid: 30), host(40), spare(41, ppid: 40), host(50), spare(51, ppid: 50),
        ]
        try writeSession(10, status: "idle")
        try writeSession(31, status: "idle", extra: #","spare":{"id":"e5f57e77"}"#)
        try write(#"{"pid":51,"kind":"bg","status":"idle","jobId":"job-1"}"#, to: "sessions/51.json")
        let job = try write(#"{"state":"working","inFlight":{"tasks":2}}"#, to: "jobs/job-1/state.json")

        let first = sample(at: 0)
        XCTAssertEqual(first.frame.agents.map(\.pid), [10, 51], "A spare with the spare key, and one with no file, are no sessions")
        let claimed = try XCTUnwrap(first.frame.agents.last)
        XCTAssertEqual(claimed.role, .session)
        XCTAssertEqual(claimed.reported?.state, .idle)
        XCTAssertEqual(claimed.backgroundJobsWorking, 1)
        XCTAssertTrue(first.watchedFiles.contains(job))
        XCTAssertEqual(first.frame.agents.first?.childCommands, 0, "The daemon and its hosts are helpers, not commands")

        try write(#"{"state":"done"}"#, to: "jobs/job-1/state.json")
        try write(#"{"pid":31,"kind":"bg","status":"busy"}"#, to: "sessions/31.json")
        let second = sample(at: 2)
        XCTAssertEqual(second.frame.agents.map(\.pid), [10, 31, 51], "The spare took a job")
        XCTAssertEqual(second.frame.agents.map(\.backgroundJobsWorking), [0, 0, 0])
        XCTAssertEqual(second.frame.agents[1].sampleInterval, 2, "The spare was a known process before it was claimed")
    }

    func testUnreadableSessionFileKeepsTheInstance() throws {
        census.rows = [claude(31, args: ["claude bg-spare", "--bg-spare", "/tmp/x.claim.sock"])]
        try write(#"{"pid":31,"kind":"bg","sta"#, to: "sessions/31.json")
        let sample = sample(at: 0)
        XCTAssertEqual(sample.frame.agents.map(\.pid), [31])
        XCTAssertNil(sample.frame.agents.first?.reported)
    }

    /// A status this build does not know is no state. It must not read as
    /// idle: the verdict then goes by the signs of activity.
    func testUnknownClaudeStatusIsNoState() throws {
        census.rows = [claude(100)]
        try writeSession(100, status: "compacting")
        let agent = try XCTUnwrap(sample(at: 0).frame.agents.first)
        XCTAssertNil(agent.reported)
        var evidence = agent
        evidence.busyChildCommands = 1
        let (verdict, _) = VerdictRules.verdict(for: evidence, memory: AgentMemory(), settings: DetectionSettings(), now: at(0))
        XCTAssertEqual(verdict, AgentVerdict(state: .working, confidence: .inferredStrong, reason: .runningCommand(1)))
    }

    /// A failed read of the process table is not "every agent is gone".
    func testUnreadableProcessTableKeepsThePreviousFrame() throws {
        census.rows = [claude(100, cpu: 5)]
        let session = try writeSession(100, status: "busy")
        let before = sample(at: 0)
        census.rows = [claude(100, cpu: 6)]
        XCTAssertEqual(sample(at: 2).frame.agents.first?.subtreeCPUSeconds, 1)

        census.unreadable = true
        for seconds in stride(from: 4.0, through: 12, by: 2) {
            let held = sample(at: seconds)
            XCTAssertEqual(held.frame.at, at(seconds))
            XCTAssertEqual(held.frame.agents.map(\.pid), [100], "at \(seconds) s")
            XCTAssertEqual(held.frame.agents.first?.reported?.state, .working)
            XCTAssertEqual(held.frame.agents.first?.sampleInterval, 0, "No CPU number for a sample that read nothing")
            XCTAssertEqual(held.roots, before.roots)
            XCTAssertEqual(held.watchedFiles, [session])
        }
        XCTAssertEqual(sample(at: 14).frame.agents, [], "A table that stays unreadable counts as empty in the end")

        census.unreadable = false
        census.rows = [claude(100, cpu: 9)]
        let back = try XCTUnwrap(sample(at: 16).frame.agents.first)
        XCTAssertEqual(back.reported?.state, .working)
        XCTAssertEqual(back.sampleInterval, 0, "After 14 seconds without a table the sample is a first one")

        // One failure between two good samples: the CPU of both intervals lands in the next one.
        census.rows = [claude(100, cpu: 10)]
        _ = sample(at: 18)
        census.unreadable = true
        XCTAssertEqual(sample(at: 20).frame.agents.count, 1)
        census.unreadable = false
        census.rows = [claude(100, cpu: 12)]
        let next = try XCTUnwrap(sample(at: 22).frame.agents.first)
        XCTAssertEqual(next.sampleInterval, 4)
        XCTAssertEqual(next.subtreeCPUSeconds, 2, accuracy: 0.0001)

        // With no frame to keep, an unreadable table gives an empty frame.
        collector = EvidenceCollector(sources: sources)
        census.unreadable = true
        XCTAssertEqual(sample(at: 24).frame.agents, [])
    }

    func testTranscriptIsReadOnlyWithoutASessionFile() throws {
        census.rows = [claude(100)]
        openFiles.directories[100] = "/Users/me/code/my.app"
        XCTAssertEqual(EvidenceCollector.claudeProjectName(forDirectory: "/Users/me/code/my.app"), "-Users-me-code-my-app")
        let toolRunning = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#
        try write(toolRunning + "\n", to: "projects/-Users-me-code-my-app/old.jsonl", modified: Date(timeIntervalSince1970: processStart - 60))
        XCTAssertNil(sample(at: 0).frame.agents.first?.reported, "A transcript from before the process started is another session's")

        let transcript = try write(toolRunning + "\n", to: "projects/-Users-me-code-my-app/new.jsonl")
        let sample = sample(at: 10)
        let agent = try XCTUnwrap(sample.frame.agents.first)
        XCTAssertEqual(agent.reported?.state, .working)
        XCTAssertEqual(agent.reported?.source, .claudeTranscript)
        XCTAssertNotNil(agent.fileActivityAt)
        XCTAssertEqual(sample.watchedFiles, [transcript])

        try writeSession(100, status: "idle")
        XCTAssertEqual(self.sample(at: 12).frame.agents.first?.reported?.source, .claudeSessionFile)
    }

    /// A file with the same time, size and inode is not read again.
    func testUnchangedFilesAreNotReadAgain() throws {
        census.rows = [claude(100)]
        let path = try writeSession(100, status: "idle")
        // A whole second, so the time can be set back exactly.
        let modified = Date(timeIntervalSince1970: (base.timeIntervalSince1970 - 30).rounded())
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        XCTAssertEqual(sample(at: 0).frame.agents.first?.reported?.state, .idle)

        let text = try String(contentsOfFile: path, encoding: .utf8).replacingOccurrences(of: "idle", with: "busy")
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        let unchanged = sample(at: 2).frame.agents.first?.reported
        XCTAssertEqual(unchanged?.state, .idle)
        XCTAssertEqual(unchanged?.observedAt, at(2), "The state was seen again at this sample")

        try FileManager.default.setAttributes([.modificationDate: modified.addingTimeInterval(1)], ofItemAtPath: path)
        XCTAssertEqual(sample(at: 4).frame.agents.first?.reported?.state, .working)
    }

    // MARK: Codex

    func testCodexEngineReadsTheRolloutsItHasOpen() throws {
        let engine = Row.fixture(25445, start: processStart, path: codexDesktopBinary, args: ["codex", "app-server"])
        let nested = Row.fixture(27648, ppid: 25445, start: processStart, path: codexDesktopBinary, args: ["codex", "app-server", "--listen", "stdio://"])
        census.rows = [engine, nested]
        let twoHoursAgo = base.addingTimeInterval(-7200)
        let dangling = try write(rollout([turnStarted]), to: "codex/2026/10/03/rollout-2026-10-03T10-00-00-01a10000-aaaa-7000-8000-00000000c78f.jsonl", modified: twoHoursAgo)
        let finished = try write(rollout([turnStarted, turnComplete]), to: "codex/2026/10/04/rollout-2026-10-04T10-00-00-01a10000-aaaa-7000-8000-00000000c780.jsonl", modified: twoHoursAgo)
        try write(rollout([turnStarted]), to: "codex/2026/10/05/rollout-2026-10-05T10-00-00-01a10000-aaaa-7000-8000-00000000c781.jsonl")
        openFiles.files[25445] = [dangling, "/Users/me/.codex/logs_2.sqlite", finished]
        openFiles.files[27648] = []

        let first = sample(at: 0)
        XCTAssertEqual(first.frame.agents.count, 1, "An engine below an engine is the same instance")
        let idle = try XCTUnwrap(first.frame.agents.first)
        XCTAssertEqual(idle.agentID, "codex-desktop")
        XCTAssertEqual(idle.role, .engine)
        XCTAssertEqual(idle.kind, .desktop)
        XCTAssertEqual(idle.reported?.state, .idle, "A turn that a killed Codex left open, in a file from before the engine started")
        XCTAssertEqual(idle.reported?.source, .codexRollout)
        XCTAssertFalse(idle.hasLiveSession)
        XCTAssertEqual(first.watchedFiles, [dangling, finished])

        let live = try write(rollout([turnStarted]), to: "codex/2026/10/05/rollout-2026-10-05T11-00-00-01a10000-aaaa-7000-8000-00000000c782.jsonl")
        openFiles.files[27648] = [live]
        let working = try XCTUnwrap(sample(at: 2).frame.agents.first)
        XCTAssertEqual(working.reported?.state, .working)
        XCTAssertEqual(working.reported?.since, Date(timeIntervalSince1970: 1_791_201_602))
        XCTAssertTrue(working.hasLiveSession)

        try write(rollout([turnStarted, turnComplete]), to: "codex/2026/10/05/rollout-2026-10-05T11-00-00-01a10000-aaaa-7000-8000-00000000c782.jsonl")
        let done = try XCTUnwrap(sample(at: 4).frame.agents.first)
        XCTAssertEqual(done.reported?.state, .idle)
        XCTAssertTrue(done.hasLiveSession, "The session file was written within the hour")

        openFiles.files = [:]
        XCTAssertNil(sample(at: 6).frame.agents.first?.reported, "The descriptors could not be read")
    }

    func testCodexTurnLongerThanOneMegabyteIsNeverIdle() throws {
        census.rows = [Row.fixture(25445, start: processStart, path: codexDesktopBinary, args: ["codex", "app-server"])]
        let output = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","output":""# + String(repeating: "x", count: 100_000) + #""}}"#
        let long = try write(rollout([turnStarted] + Array(repeating: output, count: 25)), to: "codex/2026/10/05/rollout-2026-10-05T11-00-00-01a10000-aaaa-7000-8000-00000000c782.jsonl")
        openFiles.files[25445] = [long]
        XCTAssertEqual(sample(at: 0).frame.agents.first?.reported?.state, .working)

        // A search that takes more than one sample gives no state until it is done.
        sources.rolloutSearchBudget = 1_048_576
        collector = EvidenceCollector(sources: sources)
        let searching = try XCTUnwrap(sample(at: 2).frame.agents.first)
        XCTAssertNil(searching.reported, "Unknown, not idle")
        XCTAssertNotNil(searching.fileActivityAt)
        XCTAssertNil(sample(at: 4).frame.agents.first?.reported)
        XCTAssertEqual(sample(at: 6).frame.agents.first?.reported?.state, .working)
    }

    func testCodexSessionMatchesItsRolloutByWorkingDirectory() throws {
        census.rows = [.fixture(300, start: processStart, path: "/Users/me/.codex/bin/codex", args: ["codex", "exec", "do it"])]
        openFiles.directories[300] = "/Users/me/code/demo"
        try write(rollout([meta(cwd: "/Users/me/code/other"), turnStarted]), to: "codex/2026/10/05/rollout-2026-10-05T10-00-00-01a10000-aaaa-7000-8000-00000000c781.jsonl")
        try write(rollout([meta(cwd: "/Users/me/code/demo"), turnStarted]), to: "codex/2026/10/04/rollout-2026-10-04T10-00-00-01a10000-aaaa-7000-8000-00000000c780.jsonl", modified: Date(timeIntervalSince1970: processStart - 60))
        let none = try XCTUnwrap(sample(at: 0).frame.agents.first)
        XCTAssertEqual(none.agentID, "codex")
        XCTAssertNil(none.reported, "The rollout of its directory is from before the process started")

        let own = try write(rollout([meta(cwd: "/Users/me/code/demo"), turnStarted]), to: "codex/2026/10/05/rollout-2026-10-05T11-00-00-01a10000-aaaa-7000-8000-00000000c782.jsonl")
        let sample = sample(at: EvidenceCollector.listingAge)
        XCTAssertEqual(sample.frame.agents.first?.reported?.state, .working)
        XCTAssertEqual(sample.watchedFiles.map { URL(fileURLWithPath: $0).lastPathComponent }, [URL(fileURLWithPath: own).lastPathComponent])
        XCTAssertFalse(sample.frame.agents.first?.hasLiveSession ?? true, "Only desktop apps have a live session")
    }

    // MARK: Activity

    func testActivityAgentReportsWritesToItsStore() throws {
        census.rows = [.fixture(400, start: processStart, path: "/Users/me/.opencode/bin/opencode", args: ["opencode"])]
        let store = try write("a", to: "store/opencode.db-wal")
        let first = try XCTUnwrap(sample(at: 0).frame.agents.first)
        XCTAssertEqual(first.level, .activity)
        XCTAssertNil(first.reported, "The first poll only sets the baseline")
        XCTAssertNotNil(first.fileActivityAt)
        XCTAssertNil(sample(at: 2).frame.agents.first?.reported)

        try write("ab", to: "store/opencode.db-wal")
        let third = sample(at: 4)
        let wrote = try XCTUnwrap(third.frame.agents.first)
        XCTAssertEqual(wrote.reported?.state, .working)
        XCTAssertEqual(wrote.reported?.source, .fileActivity)
        XCTAssertFalse(third.watchedFiles.contains(store), "A store that is written all the time is polled, not watched")

        census.rows = [.fixture(500, start: processStart, path: "/usr/local/bin/aider", args: ["aider"])]
        let unknown = try XCTUnwrap(sample(at: 6).frame.agents.first)
        XCTAssertEqual(unknown.agentID, "aider")
        XCTAssertNil(unknown.reported)
        XCTAssertNil(unknown.fileActivityAt)
    }

    func testUserNamesMatchAtTheGenericLevel() {
        census.rows = [.fixture(600, start: processStart, path: "/usr/local/bin/myagent", args: ["myagent"])]
        XCTAssertEqual(sample(at: 0).frame.agents.count, 0)
        self.seconds = 2
        let named = collector.collect(userNames: ["myagent"])
        XCTAssertEqual(named.frame.agents.map(\.agentID), ["user:myagent"])
        XCTAssertEqual(named.frame.agents.map(\.level), [.generic])
        XCTAssertEqual(sample(at: 4).frame.agents.count, 0)
    }

    // MARK: Process use

    func testChildCommandsAndSubtreeUse() throws {
        func rows(agent: TimeInterval, server: TimeInterval, build: TimeInterval, energy: UInt64, writes: UInt64) -> [Row] {
            [
                claude(100, cpu: agent, energy: energy, writes: writes),
                .fixture(110, ppid: 100, start: processStart, path: "/usr/local/bin/node", args: ["node", "server.js", "mcp"], cpu: server),
                .fixture(120, ppid: 100, start: processStart, path: "/bin/zsh", args: ["zsh", "-c", "make"], cpu: 0),
                .fixture(121, ppid: 120, start: processStart, path: "/usr/bin/make", args: ["make"], cpu: build),
                .fixture(130, ppid: 100, start: processStart, path: "/usr/bin/caffeinate", args: ["caffeinate", "-i", "-t", "300"]),
                claude(140, ppid: 100, args: ["claude", "daemon", "run"]),
            ]
        }
        try writeSession(100, status: "idle")
        census.rows = rows(agent: 50, server: 9, build: 3, energy: 5_000_000_000, writes: 50_000)
        let first = try XCTUnwrap(sample(at: 0).frame.agents.first)
        XCTAssertEqual(first.childCommands, 3, "The server, the shell with its build, and caffeinate")
        XCTAssertEqual(first.busyChildCommands, 0)
        XCTAssertEqual(first.subtreeCPUSeconds, 0, "What it used before the first sample is not a burst")
        XCTAssertNil(first.energyNanojoules)
        XCTAssertFalse(first.ownsSleepAssertion)

        census.rows = rows(agent: 50.01, server: 9.5, build: 4, energy: 5_010_000_000, writes: 50_010)
        assertions.pids = [130, 9999]
        let second = try XCTUnwrap(sample(at: 2).frame.agents.first)
        XCTAssertEqual(second.sampleInterval, 2)
        XCTAssertEqual(second.subtreeCPUSeconds, 1.51, accuracy: 0.0001)
        XCTAssertEqual(second.energyNanojoules, 10_000_000)
        XCTAssertEqual(second.logicalWriteBytes, 10)
        XCTAssertEqual(second.childCommands, 3)
        XCTAssertEqual(second.busyChildCommands, 0, "One burst is no running command")
        XCTAssertTrue(second.ownsSleepAssertion, "Its caffeinate child holds the assertion")

        // The build goes on and the server went quiet after its burst.
        assertions.pids = []
        var busy: [Int] = []
        for (index, seconds) in [4.0, 6, 8, 10].enumerated() {
            census.rows = rows(agent: 50.01, server: 9.5, build: 5 + TimeInterval(index), energy: 5_010_000_000, writes: 50_010)
            busy.append(sample(at: seconds).frame.agents.first?.busyChildCommands ?? -1)
        }
        XCTAssertEqual(busy, [0, 0, 1, 1], "Busy once it used the CPU in both halves of the window")

        // The build stops. It is no longer busy when the recent half is quiet.
        XCTAssertEqual(sample(at: 12).frame.agents.first?.busyChildCommands, 1)
        let later = try XCTUnwrap(sample(at: 16).frame.agents.first)
        XCTAssertEqual(later.busyChildCommands, 0)
        XCTAssertEqual(later.subtreeCPUSeconds, 0)
        XCTAssertFalse(later.ownsSleepAssertion)
    }

    /// The clock is set back by an hour, then forward again. Each sample
    /// after a step is a first sample, and the interval of the others is
    /// the awake time, whatever the date says.
    func testSampleAfterAClockStepIsAFirstSample() throws {
        var awake: TimeInterval = 9000
        sources.awakeSeconds = { awake }
        collector = EvidenceCollector(sources: sources)
        try writeSession(100, status: "idle")
        var cpu: TimeInterval = 50
        func next(at seconds: TimeInterval) throws -> EvidenceSample {
            awake += 2
            cpu += 1
            census.rows = [claude(100, cpu: cpu)]
            return sample(at: seconds)
        }
        _ = try next(at: 0)
        let second = try next(at: 2)
        XCTAssertEqual(second.frame.awake, 9004)
        XCTAssertEqual(try XCTUnwrap(second.frame.agents.first).sampleInterval, 2, accuracy: 0.001)
        XCTAssertEqual(SampleGap.length(from: second.frame.time, to: try next(at: 4).frame.time), nil)

        let back = try next(at: -3594)
        XCTAssertEqual(try XCTUnwrap(back.frame.agents.first).sampleInterval, 0, "No CPU number over the step")
        XCTAssertEqual(back.frame.awake, 9008)
        let after = try next(at: -3592)
        XCTAssertEqual(try XCTUnwrap(after.frame.agents.first).sampleInterval, 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(after.frame.agents.first).subtreeCPUSeconds, 1, accuracy: 0.001)

        let forward = try next(at: 10)
        XCTAssertEqual(try XCTUnwrap(forward.frame.agents.first).sampleInterval, 0)
        XCTAssertEqual(try XCTUnwrap(try next(at: 12).frame.agents.first).sampleInterval, 2, accuracy: 0.001)
    }

    /// The CPU deltas of the first sample after a sleep span the sleep. Over
    /// that interval a running build would read as no use at all.
    func testSampleAfterASleepIsAFirstSample() throws {
        func rows(build: TimeInterval) -> [Row] {
            [claude(100, cpu: 50), .fixture(121, ppid: 100, start: processStart, path: "/usr/bin/make", args: ["make"], cpu: build)]
        }
        try writeSession(100, status: "idle")
        var build: TimeInterval = 3
        func next(at seconds: TimeInterval) throws -> AgentEvidence {
            build += 1
            census.rows = rows(build: build)
            return try XCTUnwrap(sample(at: seconds).frame.agents.first)
        }
        var busy: [Int] = []
        for seconds in stride(from: 0.0, through: 12, by: 2) { busy.append(try next(at: seconds).busyChildCommands) }
        XCTAssertEqual(busy.last, 1)

        let woke = try next(at: 372)
        XCTAssertEqual(woke.sampleInterval, 0, "No CPU number over the sleep")
        XCTAssertNil(woke.cpuFraction)
        XCTAssertEqual(woke.childCommands, 1)
        XCTAssertEqual(woke.busyChildCommands, 0)

        let after = try next(at: 374)
        XCTAssertEqual(after.sampleInterval, 2)
        XCTAssertEqual(after.subtreeCPUSeconds, 1, accuracy: 0.0001)
        busy = []
        for seconds in stride(from: 376.0, through: 384, by: 2) { busy.append(try next(at: seconds).busyChildCommands) }
        XCTAssertEqual(busy, [0, 0, 1, 1, 1], "Busy again once both halves of a new window show use")
    }

    /// The Grep tool runs the Claude Code binary under the name ugrep.
    func testBuiltInSearchToolIsAChildCommandNotASession() throws {
        census.rows = [
            claude(100),
            .fixture(110, ppid: 100, start: processStart, path: "/bin/zsh", args: ["zsh", "-c", "ugrep"]),
            claude(111, ppid: 110, args: ["ugrep", "-G", "--hidden", "TODO"]),
        ]
        try writeSession(100, status: "busy")
        let agents = sample(at: 0).frame.agents
        XCTAssertEqual(agents.map(\.pid), [100])
        XCTAssertEqual(agents.first?.childCommands, 1)
    }

    func testOldCommandOfANewInstanceIsNotABurst() throws {
        census.rows = [claude(100)]
        try writeSession(100, status: "idle")
        _ = sample(at: 0)
        census.rows = [
            claude(100),
            .fixture(700, start: processStart, path: "/usr/local/bin/myagent", args: ["myagent"], cpu: 500),
            .fixture(701, ppid: 700, start: processStart, path: "/usr/bin/make", args: ["make"], cpu: 900),
        ]
        self.seconds = 2
        let named = collector.collect(userNames: ["myagent"])
        let agent = try XCTUnwrap(named.frame.agents.last)
        XCTAssertEqual(agent.sampleInterval, 0)
        XCTAssertEqual(agent.childCommands, 1)
        XCTAssertEqual(agent.busyChildCommands, 0)
    }

    func testInstanceDoesNotCountTheWorkOfASessionBelowIt() throws {
        census.rows = [
            claude(100, cpu: 1),
            .fixture(110, ppid: 100, start: processStart, path: "/bin/zsh", args: ["zsh"], cpu: 0),
            claude(200, ppid: 110, cpu: 1),
        ]
        try writeSession(100, status: "busy")
        try writeSession(200, status: "busy")
        _ = sample(at: 0)
        census.rows = [
            claude(100, cpu: 1),
            .fixture(110, ppid: 100, start: processStart, path: "/bin/zsh", args: ["zsh"], cpu: 0),
            claude(200, ppid: 110, cpu: 3),
        ]
        let agents = sample(at: 2).frame.agents
        XCTAssertEqual(agents.map(\.pid), [100, 200])
        XCTAssertEqual(agents.map(\.subtreeCPUSeconds), [0, 2])
        XCTAssertEqual(agents.map(\.busyChildCommands), [0, 0])
    }
}
