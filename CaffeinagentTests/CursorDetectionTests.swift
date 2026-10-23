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

/// Transcript lines with the keys of a real Cursor transcript and made-up text.
private enum Line {
    static let user = #"{"role":"user","message":{"content":[{"type":"text","text":"hello"}]}}"#
    static let assistant = #"{"role":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}"#
    static let tool = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"sleep 60"}}]}}"#
    static let ended = #"{"type":"turn_ended","status":"success"}"#

    static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
}

final class CursorTranscriptReaderTests: XCTestCase {
    func testTheNewestKnownLineDecides() {
        let cases: [(lines: [String], last: CursorTurnState.Line?, state: ReportedState?)] = [
            ([Line.user], .user, .working),
            ([Line.user, Line.assistant, Line.tool], .assistant, .working),
            ([Line.user, Line.assistant, Line.ended], .turnEnded(.success), .idle),
            ([Line.user, Line.ended, Line.user], .user, .working),
            ([Line.user, #"{"type":"turn_ended","status":"aborted"}"#], .turnEnded(.aborted), .idle),
            ([Line.user, #"{"type":"turn_ended","status":"error","error":"x"}"#], .turnEnded(.error), .idle),
            ([Line.user, #"{"type":"turn_ended","status":"new"}"#], .turnEnded(.other), .idle),
            ([Line.user, #"{"type":"turn_ended"}"#], .turnEnded(.other), .idle),
            // A line of a type this build does not know is passed over.
            ([Line.user, Line.ended, #"{"type":"metadata","x":1}"#], .turnEnded(.success), .idle),
            ([#"{"type":"metadata","x":1}"#], nil, nil),
            ([], nil, nil),
        ]
        for c in cases {
            let turn = CursorTranscriptReader.parseTail(Line.text(c.lines))
            XCTAssertEqual(turn.last, c.last, "\(c.lines)")
            XCTAssertEqual(turn.state, c.state, "\(c.lines)")
        }
        XCTAssertEqual(CursorTranscriptReader.parseTail(Line.text([Line.ended])).endStatus, .success)
        XCTAssertNil(CursorTranscriptReader.parseTail(Line.text([Line.user])).endStatus)
    }

    func testALastLineThatIsCutOffIsPassedOver() {
        let cut = Line.text([Line.user, Line.assistant]) + #"{"type":"turn_ended","sta"#
        XCTAssertEqual(CursorTranscriptReader.parseTail(cut).last, .assistant)
        let whole = Line.text([Line.user]) + Line.ended
        XCTAssertEqual(CursorTranscriptReader.parseTail(whole).last, .turnEnded(.success), "A whole last line counts without its line end")
        XCTAssertNil(CursorTranscriptReader.parseTail("{\"role\":\"us").last)
    }

    func testALineLongerThanTheFirstReadIsStillFound() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let long = #"{"role":"assistant","message":{"content":[{"type":"text","text":""# + String(repeating: "x", count: 200_000) + #""}]}}"#
        try Data(Line.text([Line.user, Line.ended, Line.user, long]).utf8).write(to: url)
        XCTAssertEqual(CursorTranscriptReader.parseTail(of: url).last, .assistant)
        try Data(Line.text([Line.user, long, Line.ended]).utf8).write(to: url)
        XCTAssertEqual(CursorTranscriptReader.parseTail(of: url).last, .turnEnded(.success))
        // The data of a later read begins inside a line.
        let tail = Data((String(repeating: "x", count: 50) + "\"}]}}\n" + Line.ended + "\n").utf8)
        XCTAssertEqual(CursorTranscriptReader.parseTail(tail, fromStart: false).last, .turnEnded(.success))
        XCTAssertNil(CursorTranscriptReader.parseTail(Data(Line.user.utf8), fromStart: false).last, "A piece of a line is no line")
    }

    func testSlugAndLabel() {
        XCTAssertEqual(CursorTranscriptReader.slug(forWorkspace: "/Users/me/code/my.app"), "Users-me-code-my-app")
        XCTAssertEqual(CursorTranscriptReader.slug(forWorkspace: "/Users/me/My Project (2)/"), "Users-me-My-Project-2")
        XCTAssertEqual(CursorTranscriptReader.slug(forWorkspace: "/tmp/a__b--c"), "tmp-a-b-c")
        XCTAssertEqual(CursorTranscriptReader.slug(forWorkspace: "/Users/me/caf\u{e9}"), "Users-me-caf")
        XCTAssertEqual(CursorTranscriptReader.label(forSlug: "Users-me-code-blog"), "blog")
        XCTAssertEqual(CursorTranscriptReader.label(forSlug: "Users-me-code-my-app"), "app", "The end of the name: a slug cannot be turned back")
        XCTAssertNil(CursorTranscriptReader.label(forSlug: "empty-window"))
        XCTAssertNil(CursorTranscriptReader.label(forSlug: ""))
    }

    func testListingFindsBothDepthsAndNoSubagents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        func write(_ path: String, age: TimeInterval) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Line.text([Line.user]).utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        let a = "0b8d6a34-7a3f-4c53-9f0e-2f6f4d1c9a11", b = "5e0f2c1d-9a4b-4e7a-8c3d-1b2a3c4d5e6f"
        try write("empty-window/agent-transcripts/\(a)/\(a).jsonl", age: 10)
        try write("empty-window/agent-transcripts/\(a)/subagents/\(b).jsonl", age: 1)
        try write("Users-me-code-blog/agent-transcripts/\(b).jsonl", age: 100)
        try write("Users-me-code-old/agent-transcripts/\(b)/\(b).jsonl", age: 90_000)
        try write("Users-me-code-blog/terminals/1.jsonl", age: 1)
        let files = CursorTranscriptReader(projectsDirectory: root).recentFiles(now: now)
        XCTAssertEqual(files.map(\.projectSlug), ["empty-window", "Users-me-code-blog"], "Newest first, none older than a day")
        XCTAssertEqual(files.map(\.sessionID), [a, b])
        XCTAssertEqual(CursorTranscriptReader(projectsDirectory: root.appendingPathComponent("none")).recentFiles(now: now), [])
    }

    func testSummaryCountsOnlyWhatThisCursorWrote() {
        let start = Date(timeIntervalSince1970: 1_791_200_000)
        func entry(_ slug: String, _ last: CursorTurnState.Line?, written: TimeInterval, since: TimeInterval? = nil) -> (file: CursorTranscriptFile, reading: CursorTranscriptTracker.Reading) {
            let at = start.addingTimeInterval(written)
            let url = URL(fileURLWithPath: "/tmp/\(slug)-\(written).jsonl")
            var signature = FileSignature(path: "/usr/bin/true")!
            signature.modifiedAt = at
            return (CursorTranscriptFile(url: url, sessionID: slug, projectSlug: slug, lastWrite: at, size: 1),
                    CursorTranscriptTracker.Reading(turn: CursorTurnState(last: last), turnSince: since.map(start.addingTimeInterval), signature: signature))
        }
        // A turn that a killed Cursor left is from before this one started.
        let dangling = CursorSummary.make(of: [entry("a", .user, written: -10)], engineStarted: start)
        XCTAssertEqual(dangling.counted, 0)
        XCTAssertNil(dangling.report(now: start), "No transcript of this run: the signs of activity decide")

        let two = CursorSummary.make(of: [entry("b", .turnEnded(.success), written: 50), entry("a", .assistant, written: 40, since: 30), entry("c", .user, written: 20, since: 20)], engineStarted: start)
        XCTAssertEqual([two.counted, two.inTurn], [3, 2])
        XCTAssertEqual(two.workingSince, start.addingTimeInterval(20), "The oldest turn in progress")
        XCTAssertEqual(two.projectSlug, "a", "The newest one in a turn")
        XCTAssertEqual(two.report(now: start)?.state, .working)
        XCTAssertEqual(two.report(now: start)?.source, .cursorTranscript)

        let ended = CursorSummary.make(of: [entry("b", .turnEnded(.aborted), written: 50), entry("a", .turnEnded(.success), written: 40)], engineStarted: start)
        XCTAssertEqual(ended.report(now: start)?.state, .idle)
        XCTAssertEqual(ended.report(now: start)?.since, start.addingTimeInterval(50))
        XCTAssertEqual(ended.projectSlug, "b")
        XCTAssertEqual(ended.ends, ["b": start.addingTimeInterval(50), "a": start.addingTimeInterval(40)], "By conversation")
        XCTAssertEqual(two.ends, ["b": start.addingTimeInterval(50)], "Only a turn that ended")
        // The status of the newest end. An error is said, and nothing of its text.
        XCTAssertEqual(ended.report(now: start)?.failed, false, "The user stopped it")
        let failed = CursorSummary.make(of: [entry("b", .turnEnded(.error), written: 50), entry("a", .turnEnded(.success), written: 40)], engineStarted: start)
        XCTAssertEqual(failed.report(now: start)?.state, .idle, "An error ends the turn as a success does")
        XCTAssertEqual(failed.report(now: start)?.failed, true)
        let before = CursorSummary.make(of: [entry("b", .turnEnded(.success), written: 50), entry("a", .turnEnded(.error), written: 40)], engineStarted: start)
        XCTAssertEqual(before.report(now: start)?.failed, false, "An older error is no news")

        // The stop hook of a conversation ends the open turn of that
        // conversation, and of no other one.
        let key = HookStateFile.sessionKey
        func stopped(_ entries: [(file: CursorTranscriptFile, reading: CursorTranscriptTracker.Reading)], _ stops: [String: TimeInterval]) -> CursorSummary {
            CursorSummary.make(of: entries, engineStarted: start, stops: Dictionary(uniqueKeysWithValues: stops.map { (key($0.key), start.addingTimeInterval($0.value)) }))
        }
        let open = [entry("a", .assistant, written: 40, since: 30), entry("c", .user, written: 20, since: 20)]
        let one = stopped(open, ["a": 45])
        XCTAssertEqual([one.counted, one.inTurn], [2, 1])
        XCTAssertEqual(one.report(now: start)?.state, .working, "The other conversation is still in its turn")
        XCTAssertEqual(one.workingSince, start.addingTimeInterval(20))
        XCTAssertEqual(one.ends, ["a": start.addingTimeInterval(45)], "It ended at the stop")
        let both = stopped(open, ["a": 45, "c": 25])
        XCTAssertEqual(both.report(now: start)?.state, .idle)
        XCTAssertEqual(both.report(now: start)?.since, start.addingTimeInterval(45))
        XCTAssertEqual(stopped(open, ["other": 45]).inTurn, 2)
        XCTAssertEqual(stopped(open, ["a": 29, "c": 19]).inTurn, 2, "A stop from before the turn began is the stop of the turn before")
        XCTAssertEqual(stopped([entry("a", .assistant, written: 40)], ["a": 25]).inTurn, 0, "With no start known, the last write decides")
        XCTAssertEqual(stopped([entry("a", .assistant, written: 41)], ["a": 25]).inTurn, 1, "A write later than the settle time after the stop is a new turn")
        // A turn that has its end line keeps the time of that line.
        XCTAssertEqual(stopped([entry("b", .turnEnded(.success), written: 50)], ["b": 60]).ends, ["b": start.addingTimeInterval(50)])

        let unknown = CursorSummary.make(of: [entry("b", nil, written: 50), entry("a", .turnEnded(.success), written: 40)], engineStarted: start)
        XCTAssertNil(unknown.report(now: start), "Idle is said only when every file was understood")
    }
}

final class CursorCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow
    private let catalog = AgentCatalog.standard
    private let app = "/Applications/Cursor.app/Contents"
    private var main: String { "\(app)/MacOS/Cursor" }
    private var plugin: String { "\(app)/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)" }
    private var helper: String { "\(app)/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper" }

    /// Shapes from `ps` on the Mac of docs/research/08-cursor.md.
    func testMatch() {
        let cases: [(name: String, path: String, args: [String], id: String?, role: AgentRole?)] = [
            ("main", main, [main], "cursor-desktop", .engine),
            ("main in another folder", "/Users/me/Applications/Cursor.app/Contents/MacOS/Cursor", ["Cursor"], "cursor-desktop", .engine),
            ("extension host", plugin, ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"], "cursor-desktop", .helper),
            ("git worker", plugin, ["Cursor Helper (Plugin)", "\(app)/Resources/app/extensions/cursor-always-local/dist/gitWorker.js"], "cursor-desktop", .helper),
            ("pty host", helper, ["Cursor Helper: terminal pty-host"], "cursor-desktop", .helper),
            ("renderer", "\(app)/Frameworks/Cursor Helper (Renderer).app/Contents/MacOS/Cursor Helper (Renderer)", ["Cursor Helper (Renderer)", "--type=renderer"], "cursor-desktop", .helper),
            ("gpu", "\(app)/Frameworks/Cursor Helper (GPU).app/Contents/MacOS/Cursor Helper (GPU)", ["Cursor Helper (GPU)", "--type=gpu-process"], "cursor-desktop", .helper),
            ("crash handler", "\(app)/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler", ["chrome_crashpad_handler"], "cursor-desktop", .helper),
            // Nothing of the bundle is a CLI, whatever it is told to run.
            ("bundled node runs a script named like a CLI", "\(app)/Resources/app/resources/helpers/node", ["node", "/opt/homebrew/bin/gemini"], "cursor-desktop", .helper),
            ("helper with a title that names a CLI", plugin, ["codex", "app-server"], "cursor-desktop", .helper),
            ("helper as node with a codex script", plugin, ["node", "/Users/me/.local/bin/codex", "exec"], "cursor-desktop", .helper),
            ("bundled launcher", "\(app)/Resources/app/bin/cursor", ["cursor", "."], "cursor-desktop", .helper),
            ("cursor --wait", main, [main, "\(app)/Resources/app/out/cli.js", "--wait", "COMMIT_EDITMSG"], "cursor-desktop", .helper),
            ("cursor --wait of a copy in another folder", "/Users/me/Applications/Cursor.app/Contents/MacOS/Cursor", ["/Users/me/Applications/Cursor.app/Contents/MacOS/Cursor", "/Users/me/Applications/Cursor.app/Contents/Resources/app/out/cli.js", "--wait", "a.txt"], "cursor-desktop", .helper),
            ("main that opens a file named cli.js", main, [main, "/Users/me/code/tool/cli.js"], "cursor-desktop", .engine),
            // The same command of the other editors is inside a bundle
            // with no engine at that path, so it is no agent.
            ("code --wait", "/Applications/Visual Studio Code.app/Contents/MacOS/Code", ["/Applications/Visual Studio Code.app/Contents/MacOS/Code", "/Applications/Visual Studio Code.app/Contents/Resources/app/out/cli.js", "--wait", "a.txt"], nil, nil),
            ("antigravity --wait", "/Applications/Antigravity.app/Contents/MacOS/Antigravity", ["/Applications/Antigravity.app/Contents/MacOS/Antigravity", "/Applications/Antigravity.app/Contents/Resources/app/out/cli.js", "--wait", "a.txt"], nil, nil),
            ("windsurf --wait", "/Applications/Windsurf.app/Contents/MacOS/Electron", ["/Applications/Windsurf.app/Contents/MacOS/Electron", "/Applications/Windsurf.app/Contents/Resources/app/out/cli.js", "--wait", "a.txt"], nil, nil),
            ("the CLI", "/Users/me/.local/bin/cursor-agent", ["cursor-agent"], "cursor-agent", .session),
            ("another app named Cursor inside", "/Applications/Other.app/Contents/MacOS/Cursor", ["Cursor"], nil, nil),
            ("system cursor service", "/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService", ["CursorUIViewService"], nil, nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: c.path, args: c.args), userNames: [])
            XCTAssertEqual(match?.definition.id, c.id, c.name)
            XCTAssertEqual(match?.role, c.role, c.name)
        }
        let definition = catalog.definitions.first { $0.id == "cursor-desktop" }
        XCTAssertEqual(definition?.displayName, "Cursor")
        XCTAssertEqual(definition?.level, .state)
        XCTAssertEqual(definition?.verified, true)
        XCTAssertEqual(catalog.definitions.first { $0.id == "cursor-agent" }?.displayName, "Cursor CLI")
    }

    func testCursorIsOneInstanceAndAnAgentInItsTerminalIsItsOwn() {
        let snapshot: [Row] = [
            .fixture(500, path: main, args: [main]),
            .fixture(510, ppid: 500, path: plugin, args: ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"]),
            .fixture(511, ppid: 500, path: plugin, args: ["Cursor Helper (Plugin): extension-host (user) [2-1]"]),
            .fixture(520, ppid: 510, path: "/bin/zsh", args: ["/bin/zsh", "-c", "sleep 60"]),
            .fixture(521, ppid: 520, path: "/bin/sleep", args: ["sleep", "60"]),
            .fixture(530, ppid: 500, path: helper, args: ["Cursor Helper: terminal pty-host"]),
            .fixture(531, ppid: 530, path: "/bin/zsh", args: ["-zsh"], tty: 5),
            .fixture(532, ppid: 531, path: "/Users/me/.local/share/claude/versions/2.1.289", args: ["claude"], tty: 5),
        ]
        let instances = catalog.instances(in: snapshot)
        XCTAssertEqual(instances.map(\.definitionID), ["cursor-desktop", "claude"])
        XCTAssertEqual(instances.first?.rootPID, 500)
        XCTAssertEqual(Set(instances.first?.rows.map(\.pid) ?? []), [500, 510, 511, 520, 521, 530, 531])
    }

    /// `git commit` in Terminal with `cursor --wait` as the editor. It was
    /// a second Cursor that read every transcript again: a wrong wait, and
    /// "finished" told twice.
    func testTheShellCommandThatWaitsIsNoSecondCursor() {
        let cli = "\(app)/Resources/app/out/cli.js"
        let snapshot: [Row] = [
            .fixture(500, path: main, args: [main]),
            .fixture(510, ppid: 500, path: plugin, args: ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"]),
            .fixture(700, path: "/bin/zsh", args: ["-zsh"], tty: 7),
            .fixture(710, ppid: 700, path: "/bin/bash", args: ["bash", "\(app)/Resources/app/bin/cursor", "--wait", "COMMIT_EDITMSG"], tty: 7),
            .fixture(711, ppid: 710, path: main, args: [main, cli, "--wait", "COMMIT_EDITMSG"], tty: 7),
        ]
        let instances = catalog.instances(in: snapshot)
        XCTAssertEqual(instances.map(\.rootPID), [500])
        XCTAssertNil(HookCommand.agentProcess(in: [snapshot[4], snapshot[3], snapshot[2]], hookAgent: "cursor"))
    }

    func testAgentCommandIsAShellBelowAnExtensionHost() {
        let host = Row.fixture(510, path: plugin, args: ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"])
        let pty = Row.fixture(530, path: helper, args: ["Cursor Helper: terminal pty-host"])
        let shell = Row.fixture(520, ppid: 510, path: "/bin/zsh", args: ["/bin/zsh", "-c", "make"])
        XCTAssertTrue(AgentCatalog.isCursorAgentCommand(shell, parent: host))
        XCTAssertTrue(AgentCatalog.isCursorAgentCommand(.fixture(520, ppid: 510, path: "/opt/homebrew/bin/fish", args: ["fish", "-c", "make"]), parent: host))
        XCTAssertFalse(AgentCatalog.isCursorAgentCommand(shell, parent: pty), "A terminal of the user")
        XCTAssertFalse(AgentCatalog.isCursorAgentCommand(.fixture(540, ppid: 510, path: "/Users/me/.cargo/bin/rust-analyzer", args: ["rust-analyzer"]), parent: host), "A language server")
        XCTAssertFalse(AgentCatalog.isCursorAgentCommand(shell, parent: .fixture(9, path: "/Applications/Other.app/Contents/Frameworks/Cursor Helper (Plugin)", args: [])))
    }
}

/// The whole way for Cursor: files and processes in, the verdict, the hold
/// and the notifications out, one sample per second.
final class CursorTimelineTests: XCTestCase {
    typealias Row = ProcessInfoRow

    /// A whole second: a file keeps its write time less exactly than a `Date`.
    private let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }
    private let app = "/Applications/Cursor.app/Contents"
    private let chatA = "0b8d6a34-7a3f-4c53-9f0e-2f6f4d1c9a11"
    private let chatB = "5e0f2c1d-9a4b-4e7a-8c3d-1b2a3c4d5e6f"

    private var root: URL!
    private var census: FakeCensus!
    private var assertions: FakeAssertions!
    private var collector: EvidenceCollector!
    private var seconds: TimeInterval = 0
    private var agentMemory: [ProcessIdentity: AgentMemory] = [:]
    private var policyMemory = PolicyMemory()
    private var reducer = AgentNoticeReducer()
    private var told: [(at: TimeInterval, notice: AgentNotice)] = []
    private var settings = DetectionSettings()

    struct Step {
        var sample: EvidenceSample
        var evidence: AgentEvidence?
        var reading: AgentReading?
        var decision: HoldDecision
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        census = FakeCensus()
        assertions = FakeAssertions()
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: FakePower(), openFiles: FakeOpenFiles())
        sources.cursorTranscripts = CursorTranscriptReader(projectsDirectory: root)
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
        census.rows = cursor()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private var hostPath: String { "\(app)/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)" }

    private func cursor(extra: [Row] = []) -> [Row] {
        [
            .fixture(500, start: processStart, path: "\(app)/MacOS/Cursor", args: ["\(app)/MacOS/Cursor"]),
            .fixture(510, ppid: 500, start: processStart, path: hostPath, args: ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"]),
            .fixture(530, ppid: 500, start: processStart, path: "\(app)/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper", args: ["Cursor Helper: terminal pty-host"]),
        ] + extra
    }

    /// The shell of an agent command with the command below it.
    private func command(cpu: TimeInterval = 0) -> [Row] {
        [
            .fixture(520, ppid: 510, start: processStart + 500, path: "/bin/zsh", args: ["/bin/zsh", "-c", "sleep 60"]),
            .fixture(521, ppid: 520, start: processStart + 500, path: "/bin/sleep", args: ["sleep", "60"], cpu: cpu),
        ]
    }

    /// Writes the whole file anew, as Cursor's writer can.
    private func write(_ lines: [String], chat: String, slug: String = "empty-window", at seconds: TimeInterval) throws {
        let url = root.appendingPathComponent("\(slug)/agent-transcripts/\(chat)/\(chat).jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Line.text(lines).utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: at(seconds)], ofItemAtPath: url.path)
    }

    @discardableResult
    private func step(_ seconds: TimeInterval) -> Step {
        self.seconds = seconds
        let sample = collector.collect()
        let (readings, memory) = VerdictRules.readings(for: sample.frame, memory: agentMemory, settings: settings)
        agentMemory = memory
        let (decision, policy) = HoldPolicy.decide(
            readings: readings, memory: policyMemory, mode: .agentWorking, enabled: true, entitlement: nil, safety: nil,
            settings: settings, context: sample.frame.context, now: sample.frame.at
        )
        policyMemory = policy
        let notices = reducer.update(AgentNoticeInput(readings: readings, settings: AgentNoticeSettings(waiting: true, finished: true, onlyWhenAway: false)), now: sample.frame.at)
        told += notices.map { (seconds, $0) }
        return Step(sample: sample, evidence: sample.frame.agents.first, reading: readings.first, decision: decision)
    }

    /// One sample per second, and the last one.
    @discardableResult
    private func run(_ range: ClosedRange<Int>, check: ((Step, Int) -> Void)? = nil) -> Step {
        var last: Step?
        for second in range {
            let step = step(TimeInterval(second))
            check?(step, second)
            last = step
        }
        return last!
    }

    func testPromptStreamingAndALongSilentCommand() throws {
        try write([Line.user, Line.ended], chat: chatA, at: -100)
        let idle = run(0...9)
        XCTAssertEqual(idle.evidence?.agentID, "cursor-desktop")
        XCTAssertEqual(idle.evidence?.pid, 500, "The main process is the instance")
        XCTAssertEqual(idle.evidence?.reported?.state, .idle)
        XCTAssertEqual(idle.reading?.verdict.reason, .atPrompt)
        XCTAssertFalse(idle.decision.hold)
        XCTAssertTrue(idle.evidence?.hasLiveSession ?? false, "A transcript of the last hour")

        // The prompt: a user line, and Cursor takes its wake lock.
        try write([Line.user, Line.ended, Line.user], chat: chatA, at: 10)
        assertions.pids = [500]
        let prompt = step(10)
        XCTAssertEqual(prompt.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertEqual(prompt.reading?.turn, AgentTurn(state: .working, since: at(10)), "The write of the user line is the start of the turn")
        XCTAssertTrue(prompt.evidence?.ownsSleepAssertion ?? false)
        XCTAssertTrue(prompt.decision.hold)

        try write([Line.user, Line.ended, Line.user, Line.assistant], chat: chatA, at: 20)
        run(11...29) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        // The command runs for 65 seconds and the transcript is not written.
        try write([Line.user, Line.ended, Line.user, Line.assistant, Line.tool], chat: chatA, at: 30)
        census.rows = cursor(extra: command())
        run(30...94) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)")
            XCTAssertEqual(step.reading?.turn, AgentTurn(state: .working, since: self.at(10)), "\(second)")
            XCTAssertEqual(step.evidence?.childCommands, 1, "\(second)")
            XCTAssertTrue(step.decision.hold, "\(second)")
        }
        // A command with no assertion is still no wait.
        assertions.pids = []
        run(95...120) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }

        census.rows = cursor()
        try write([Line.user, Line.ended, Line.user, Line.assistant, Line.tool, Line.ended], chat: chatA, at: 121)
        let ended = step(121)
        XCTAssertEqual(ended.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertEqual(ended.decision.perAgent.first?.cause, .finishedRecently)
        run(122...240) { step, second in XCTAssertEqual(step.decision.hold, second < 120 + 120, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
        XCTAssertEqual(told.first?.at, 123, "After the debounce")
        XCTAssertEqual(told.first?.notice.sessions.first?.workedFor ?? 0, 111, accuracy: 0.5)
    }

    func testCursorThatQuitsInTheMiddleOfATurnIsGone() throws {
        try write([Line.user], chat: chatA, at: 0)
        assertions.pids = [500]
        XCTAssertEqual(run(0...5).reading?.verdict.state, .working)
        census.rows = []
        let gone = step(6)
        XCTAssertNil(gone.evidence)
        XCTAssertFalse(gone.decision.hold)
        XCTAssertEqual(gone.decision.headline, .noAgents)
    }

    func testATurnThatAnEarlierCursorLeftIsIgnored() throws {
        // Written before this Cursor started, and it never got its end.
        try write([Line.user, Line.assistant], chat: chatA, at: -700)
        run(0...30) { step, second in
            XCTAssertNil(step.evidence?.reported, "\(second)")
            XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)")
            XCTAssertFalse(step.evidence?.hasLiveSession ?? true, "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
        XCTAssertTrue(told.isEmpty)
        // The next prompt in that conversation is this Cursor's.
        try write([Line.user, Line.assistant, Line.user], chat: chatA, at: 31)
        XCTAssertEqual(run(31...40).reading?.verdict.state, .working, "Found by the next listing")
    }

    func testAssertionDropIsAWaitThatIsHeldAndThenReleased() throws {
        XCTAssertTrue(CursorApprovalRule.enabled)
        let settle = Int(CursorApprovalRule.settle)
        try write([Line.user, Line.tool], chat: chatA, slug: "Users-me-code-blog", at: 0)
        assertions.pids = [500]
        XCTAssertEqual(run(0...29).reading?.verdict.state, .working)
        // Cursor asks for an approval and gives up its wake lock.
        assertions.pids = []
        run(30...(30 + settle - 1)) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        let waitStart = 30 + settle
        let waits = step(TimeInterval(waitStart))
        XCTAssertEqual(waits.reading?.verdict, AgentVerdict(state: .waitingForUser, confidence: .inferredStrong, reason: .awaitsApproval))
        XCTAssertEqual(waits.reading?.verdict.reason.text, "Waiting for your approval")
        XCTAssertEqual(waits.reading?.turn, AgentTurn(state: .waitingForUser))
        XCTAssertEqual(waits.decision.headline, .waitingHeld(.one("Cursor")))
        XCTAssertEqual(waits.sample.sessionHints.values.first?.name, "blog")
        // The inputs are in the frame.
        XCTAssertEqual(waits.evidence?.reported?.source, .cursorTranscript)
        XCTAssertEqual(waits.evidence?.reported?.state, .working)
        XCTAssertFalse(waits.evidence?.ownsSleepAssertion ?? true)
        XCTAssertEqual(waits.evidence?.childCommands, 0)

        run((waitStart + 1)...(waitStart + 320)) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .waitingForUser, "\(second)")
            XCTAssertEqual(step.decision.hold, second < waitStart + 300, "\(second)")
        }
        XCTAssertEqual(told.map(\.notice.kind), [.waiting])
        XCTAssertEqual(told.first?.at, TimeInterval(waitStart + 3))
        XCTAssertEqual(step(TimeInterval(waitStart + 321)).decision.headline, .waitingReleased(.one("Cursor")))

        // The approval: the wake lock is back, and the command runs.
        assertions.pids = [500]
        census.rows = cursor(extra: command())
        let approved = step(TimeInterval(waitStart + 322))
        XCTAssertEqual(approved.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertTrue(approved.decision.hold)
        try write([Line.user, Line.tool, Line.ended], chat: chatA, slug: "Users-me-code-blog", at: TimeInterval(waitStart + 330))
        assertions.pids = []
        census.rows = cursor()
        run((waitStart + 323)...(waitStart + 340))
        XCTAssertEqual(told.map(\.notice.kind), [.waiting, .finished])
    }

    /// The times of the approval wait that was measured on 2026-10-07
    /// (docs/research/08b-cursor-live-run.md), with the prompt at 0.
    func testTheMeasuredApprovalWait() throws {
        try write([Line.user, Line.ended], chat: chatA, at: -100)
        run(-5...(-1))
        assertions.pids = [500]
        run(0...2) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second): only the assertion yet") }
        try write([Line.user, Line.ended, Line.user, Line.tool], chat: chatA, at: 3)
        run(3...12) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        // The approval prompt is shown, and the assertion is released.
        assertions.pids = []
        // The user's own work in the editor's terminal blocks nothing.
        census.rows = cursor(extra: [
            .fixture(531, ppid: 530, start: processStart, path: "/bin/zsh", args: ["-zsh"], tty: 5),
            .fixture(532, ppid: 531, start: processStart, path: "/usr/bin/xcodebuild", args: ["xcodebuild", "test"], tty: 5),
        ])
        run(13...27) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        // 12 minutes with the turn open, no assertion, no command, no write.
        run(28...774) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .waitingForUser, "\(second)")
            XCTAssertEqual(step.decision.hold, second < 28 + 300, "\(second)")
        }
        XCTAssertEqual(told.map(\.notice.kind), [.waiting])
        XCTAssertEqual(told.first?.at, 31, "After the settle time and the debounce")
        // The user presses Run: the assertion is back for 6 seconds.
        assertions.pids = [500]
        run(775...780) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)")
            XCTAssertTrue(step.decision.hold, "\(second)")
        }
        // The end line comes 9 seconds after the assertion went.
        assertions.pids = []
        run(781...789) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second): no wait at the end of a turn") }
        try write([Line.user, Line.ended, Line.user, Line.tool, Line.assistant, Line.ended], chat: chatA, at: 790)
        XCTAssertEqual(run(790...800).reading?.verdict.state, .idle)
        XCTAssertEqual(told.map(\.notice.kind), [.waiting, .finished], "No second wait is told")
    }

    func testAShortDropOfTheAssertionIsNoWait() throws {
        try write([Line.user, Line.assistant], chat: chatA, at: 0)
        assertions.pids = [500]
        run(0...9)
        assertions.pids = []
        run(10...23) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        assertions.pids = [500]
        run(24...60) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        XCTAssertTrue(told.isEmpty)
    }

    func testTheWholeFileWrittenAnewKeepsTheTurn() throws {
        try write([Line.user], chat: chatA, at: 0)
        assertions.pids = [500]
        XCTAssertEqual(run(0...4).reading?.turn, AgentTurn(state: .working, since: at(0)))
        // A new file at the path, longer and then shorter.
        try write([Line.user, Line.assistant, Line.tool, Line.assistant], chat: chatA, at: 5)
        XCTAssertEqual(step(5).reading?.turn, AgentTurn(state: .working, since: at(0)))
        try write([Line.assistant], chat: chatA, at: 6)
        XCTAssertEqual(step(6).reading?.turn, AgentTurn(state: .working, since: at(0)))
        try write([Line.user, Line.ended], chat: chatA, at: 7)
        assertions.pids = []
        XCTAssertEqual(step(7).reading?.verdict.state, .idle)
        try write([Line.user, Line.ended, Line.user], chat: chatA, at: 8)
        XCTAssertEqual(step(8).reading?.turn, AgentTurn(state: .working, since: at(8)), "A new turn has a new start")
    }

    func testTwoConversationsAndOneEnds() throws {
        try write([Line.user], chat: chatA, slug: "Users-me-code-blog", at: 0)
        try write([Line.user], chat: chatB, slug: "Users-me-code-site", at: 2)
        assertions.pids = [500]
        let both = run(0...10)
        XCTAssertEqual(both.sample.frame.agents.count, 1, "One row for the app")
        XCTAssertEqual(both.reading?.turn, AgentTurn(state: .working, since: at(0)))
        XCTAssertEqual(both.sample.sessionHints.values.first?.name, "site", "The newest one in a turn")

        try write([Line.user, Line.ended], chat: chatB, slug: "Users-me-code-site", at: 11)
        run(11...40) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        XCTAssertEqual(step(41).sample.sessionHints.values.first?.name, "blog")
        XCTAssertTrue(told.isEmpty, "The app still works")

        try write([Line.user, Line.ended], chat: chatA, slug: "Users-me-code-blog", at: 42)
        assertions.pids = []
        XCTAssertEqual(run(42...50).reading?.verdict.state, .idle)
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
    }

    func testABusyProcessBelowAnIdleCursorIsNoWork() throws {
        try write([Line.user, Line.ended], chat: chatA, at: -100)
        // A search of the editor at full speed, a build in the terminal,
        // and a shell below the extension host, all with no turn.
        func rows(_ cpu: TimeInterval) -> [Row] {
            cursor(extra: command(cpu: cpu) + [
                .fixture(531, ppid: 530, start: processStart, path: "/bin/zsh", args: ["-zsh"], tty: 5),
                .fixture(532, ppid: 531, start: processStart, path: "/usr/bin/make", args: ["make"], tty: 5, cpu: cpu),
                .fixture(540, ppid: 510, start: processStart, path: "/usr/local/bin/ugrep", args: ["ugrep", "-G", "x"], cpu: cpu),
            ])
        }
        for second in 0...60 {
            census.rows = rows(TimeInterval(second))
            let step = step(TimeInterval(second))
            XCTAssertEqual(step.evidence?.childCommands, 0, "\(second)")
            XCTAssertEqual(step.evidence?.busyChildCommands, 0, "\(second)")
            XCTAssertEqual(step.evidence?.subtreeCPUSeconds, 0, "\(second)")
            XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt), "\(second)")
            XCTAssertFalse(step.decision.hold, "\(second)")
        }
        // In a turn the agent's shell counts, and only that.
        try write([Line.user, Line.ended, Line.user, Line.tool], chat: chatA, at: 61)
        var last: Step?
        for second in 61...80 {
            census.rows = rows(TimeInterval(second))
            last = step(TimeInterval(second))
            XCTAssertEqual(last?.evidence?.childCommands, 1, "\(second)")
        }
        XCTAssertEqual(last?.evidence?.busyChildCommands, 1)
        XCTAssertEqual(last?.reading?.verdict.state, .working)
    }

    func testWithNoTranscriptTheAssertionIsTheSign() {
        // Transcripts can be switched off in Cursor.
        let quiet = run(0...5)
        XCTAssertNil(quiet.evidence?.reported)
        XCTAssertEqual(quiet.reading?.verdict.state, .idle)
        assertions.pids = [500]
        XCTAssertEqual(step(6).reading?.verdict, AgentVerdict(state: .working, confidence: .inferredStrong, reason: .holdsSleepAssertion))
        // A `caffeinate` in the editor's terminal is not Cursor's wake lock.
        assertions.pids = [532]
        census.rows = cursor(extra: [.fixture(532, ppid: 530, start: processStart, path: "/usr/bin/caffeinate", args: ["caffeinate"])])
        XCTAssertFalse(step(7).evidence?.ownsSleepAssertion ?? true)
    }

    func testTheHookStateLandsOnTheMainProcess() throws {
        let hooks = root.appendingPathComponent("hooks")
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: FakePower(), openFiles: FakeOpenFiles())
        sources.cursorTranscripts = CursorTranscriptReader(projectsDirectory: root.appendingPathComponent("projects"))
        sources.hookDirectory = hooks
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
        // The hook runs below a shell that the extension host started.
        let chain: [Row] = [
            .fixture(600, ppid: 510, path: "/bin/sh", args: ["sh", "-c", "hook"]),
            census.rows[1], census.rows[0],
        ]
        XCTAssertTrue(HookCommand.record(agent: "cursor", event: "beforeSubmitPrompt", input: Array(#"{"conversation_id":"c1"}"#.utf8), chain: chain, directory: hooks, now: at(0)))
        let working = step(1)
        XCTAssertEqual(working.evidence?.hookState, .working)
        XCTAssertEqual(working.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertTrue(HookCommand.record(agent: "cursor", event: "stop", input: Array(#"{"conversation_id":"c1","status":"completed"}"#.utf8), chain: chain, directory: hooks, now: at(2)))
        XCTAssertEqual(step(3).reading?.verdict.state, .idle)
    }

    /// Measured on 2026-10-07 with the hooks on, at the usage limit: the
    /// prompt of each of two conversations, 9 seconds apart, failed at
    /// once. The hook said working, the transcript got its one line, a
    /// `turn_ended` with the status `error`, a second later, and no `stop`
    /// came. No assertion, no command. Cursor read as working for 60
    /// seconds after the second prompt. A new transcript is found by the
    /// next listing, so the end is seen up to `listingAge` late.
    func testAPromptThatFailsAtOnceWithTheHooksOnIsIdleAtOnce() throws {
        let hooks = root.appendingPathComponent("hooks")
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: FakePower(), openFiles: FakeOpenFiles())
        sources.cursorTranscripts = CursorTranscriptReader(projectsDirectory: root.appendingPathComponent("projects"))
        sources.hookDirectory = hooks
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
        let chain: [Row] = [.fixture(600, ppid: 510, path: "/bin/sh", args: ["sh", "-c", "hook"]), census.rows[1], census.rows[0]]
        let failed = #"{"type":"turn_ended","status":"error","error":"x"}"#
        func prompt(_ chat: String, at seconds: TimeInterval) {
            XCTAssertTrue(HookCommand.record(agent: "cursor", event: "beforeSubmitPrompt", input: Array(#"{"conversation_id":"\#(chat)"}"#.utf8), chain: chain, directory: hooks, now: at(seconds)))
        }
        func fail(_ chat: String, at seconds: TimeInterval) throws {
            try write([failed], chat: chat, slug: "projects/Users-me-code-blog", at: seconds)
        }

        prompt(chatA, at: 0)
        XCTAssertEqual(step(0).reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        try fail(chatA, at: 1)
        run(1...8) { step, second in
            if second >= 5 { XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt), "\(second)") }
        }
        // The second conversation: its prompt is newer than the end of the first.
        prompt(chatB, at: 9)
        XCTAssertEqual(step(9).reading?.verdict.state, .working)
        try fail(chatB, at: 10)
        run(10...200) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)")
            XCTAssertEqual(step.reading?.turn?.state, .idle, "\(second)")
            XCTAssertEqual(step.decision.hold, second < 9 + 120, "\(second): the release time after the last second of work")
        }
        XCTAssertEqual(told.map(\.notice.kind), [.finished, .finished])
        XCTAssertEqual(told.map(\.at), [7, 12], "After the debounce")
        let titles = told.map { AgentNoticeText.content($0.notice, outlook: .silent, now: at(200)).title }
        XCTAssertEqual(titles, ["Cursor stopped with an error", "Cursor stopped with an error"])
    }

    /// Two conversations with the hooks on. B began before the hooks were
    /// on and waits for an approval. A runs a turn and the user stops it:
    /// its transcript keeps the open last line. The stop of A ended B too,
    /// and Cursor read as idle while B waited.
    func testTheStopOfOneConversationDoesNotEndAnotherThatWaitsForApproval() throws {
        let hooks = root.appendingPathComponent("hooks")
        var sources = EvidenceCollector.Sources(census: census, assertions: assertions, power: FakePower(), openFiles: FakeOpenFiles())
        sources.cursorTranscripts = CursorTranscriptReader(projectsDirectory: root.appendingPathComponent("projects"))
        sources.hookDirectory = hooks
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
        let chain: [Row] = [.fixture(600, ppid: 510, path: "/bin/sh", args: ["sh", "-c", "hook"]), census.rows[1], census.rows[0]]
        let slug = "projects/Users-me-code-blog"
        func hook(_ event: String, _ chat: String, at seconds: TimeInterval) {
            XCTAssertTrue(HookCommand.record(agent: "cursor", event: event, input: Array(#"{"conversation_id":"\#(chat)"}"#.utf8), chain: chain, directory: hooks, now: at(seconds)))
        }
        try write([Line.user, Line.ended], chat: chatA, slug: slug, at: -100)
        try write([Line.user, Line.ended], chat: chatB, slug: slug, at: -100)
        XCTAssertEqual(run(0...4).reading?.verdict.state, .idle)

        // B: a prompt with no hook event, and then an approval is pending.
        try write([Line.user, Line.ended, Line.user, Line.tool], chat: chatB, slug: slug, at: 5)
        assertions.pids = [500]
        run(5...14) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        assertions.pids = []
        XCTAssertEqual(run(15...39).reading?.verdict, AgentVerdict(state: .waitingForUser, confidence: .inferredStrong, reason: .awaitsApproval))

        // A: a turn of 10 seconds that the user stops.
        hook("beforeSubmitPrompt", chatA, at: 40)
        try write([Line.user, Line.ended, Line.user], chat: chatA, slug: slug, at: 40)
        assertions.pids = [500]
        run(40...49) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        hook("stop", chatA, at: 50)
        assertions.pids = []
        run(50...400) { step, second in
            XCTAssertNotEqual(step.reading?.verdict.state, .idle, "\(second)")
            if second >= 50 + Int(CursorApprovalRule.settle) {
                XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .waitingForUser, confidence: .inferredStrong, reason: .awaitsApproval), "\(second)")
            }
        }

        // The user answers B and its turn ends. A still has its open last
        // line, and its own stop ends it.
        try write([Line.user, Line.ended, Line.user, Line.tool, Line.ended], chat: chatB, slug: slug, at: 401)
        run(401...500) { step, second in
            if second >= 405 { XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        }
    }
}

final class CursorApprovalRuleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func cursor(
        _ state: ReportedState? = .working, at seconds: TimeInterval, assertion: Bool = false, commands: Int = 0,
        source: StateReport.Source = .cursorTranscript, hook: ReportedState? = nil, id: String = "cursor-desktop",
        hookAt: TimeInterval? = nil, writeAt: TimeInterval? = nil
    ) -> AgentEvidence {
        AgentEvidence(
            agentID: id, displayName: "Cursor", level: .state, kind: .desktop, role: .engine, pid: 500, startTime: start.timeIntervalSince1970 - 600,
            reported: state.map { StateReport(state: $0, since: at(0), observedAt: at(seconds), source: source, detail: nil) },
            childCommands: commands, sampleInterval: 1, fileActivityAt: writeAt.map(at), ownsSleepAssertion: assertion,
            hookState: hook, hookStateAt: hook.map { _ in at(hookAt ?? seconds) }
        )
    }

    /// The state at each second of a timeline.
    private func states(to end: Int, _ make: (TimeInterval) -> AgentEvidence) -> [WorkState] {
        var memory: [ProcessIdentity: AgentMemory] = [:]
        return (0...end).map { second in
            let frame = EvidenceFrame(at: at(TimeInterval(second)), agents: [make(TimeInterval(second))])
            let (readings, next) = VerdictRules.readings(for: frame, memory: memory, settings: DetectionSettings())
            memory = next
            XCTAssertEqual(readings[0].turn?.state, readings[0].verdict.state, "\(second)")
            return readings[0].verdict.state
        }
    }

    func testTheSigns() {
        XCTAssertTrue(CursorApprovalRule.signs(turnInProgress: true, holdsAssertion: false, childCommands: 0))
        XCTAssertFalse(CursorApprovalRule.signs(turnInProgress: false, holdsAssertion: false, childCommands: 0))
        XCTAssertFalse(CursorApprovalRule.signs(turnInProgress: true, holdsAssertion: true, childCommands: 0))
        XCTAssertFalse(CursorApprovalRule.signs(turnInProgress: true, holdsAssertion: false, childCommands: 1))
        XCTAssertTrue(CursorApprovalRule.signs(of: cursor(at: 0)))
        XCTAssertFalse(CursorApprovalRule.signs(of: cursor(.idle, at: 0)))
        XCTAssertFalse(CursorApprovalRule.signs(of: cursor(nil, at: 0)))
        XCTAssertFalse(CursorApprovalRule.signs(of: cursor(at: 0, source: .codexRollout)))
        XCTAssertFalse(CursorApprovalRule.signs(of: cursor(at: 0, id: "codex-desktop")), "A rule for Cursor only")
        XCTAssertFalse(CursorApprovalRule.signs(of: cursor(at: 0, hook: .idle)), "Cursor's stop hook says the turn is over")
        XCTAssertTrue(CursorApprovalRule.signs(of: cursor(at: 0, hook: .working)), "No hook event exists for an approval")
    }

    func testTheSettleTimeAndTheSwitch() {
        XCTAssertEqual(CursorApprovalRule.settle, 15)
        XCTAssertFalse(CursorApprovalRule.waits(signsSince: nil, now: at(100)))
        XCTAssertFalse(CursorApprovalRule.waits(signsSince: at(0), now: at(14.9)))
        XCTAssertTrue(CursorApprovalRule.waits(signsSince: at(0), now: at(15)))
        XCTAssertFalse(CursorApprovalRule.waits(signsSince: at(0), now: at(1000), enabled: false), "Switched off: the turn is working")
        XCTAssertTrue(CursorApprovalRule.waits(signsSince: at(0), now: at(4), settle: 4))
    }

    func testWaitingStartsAfterTheSettleTimeAndEndsAtOnce() {
        let timeline = states(to: 60) { second in
            self.cursor(at: second, assertion: second < 20 || second >= 50)
        }
        XCTAssertEqual(Array(timeline[0..<35]), Array(repeating: .working, count: 35))
        XCTAssertEqual(Array(timeline[35..<50]), Array(repeating: .waitingForUser, count: 15))
        XCTAssertEqual(Array(timeline[50...60]), Array(repeating: .working, count: 11))
    }

    func testACommandOrABreakStartsTheCountAgain() {
        // The signs hold for 8 seconds, break for one, and hold again.
        let timeline = states(to: 30) { second in
            self.cursor(at: second, commands: second == 8 ? 1 : 0)
        }
        XCTAssertEqual(timeline.firstIndex(of: .waitingForUser), 24)
    }

    func testAFreshHookWorkingDoesNotHideTheWait() {
        let timeline = states(to: 20) { second in self.cursor(at: second, hook: .working) }
        XCTAssertEqual(timeline.firstIndex(of: .waitingForUser), 15)
    }

    /// The hooks are on and the user stops a turn at 30 s. The transcript
    /// keeps its open last line. Cursor read as working for a minute and
    /// then for as long as the file was listed.
    func testAStopHookEndsATurnThatGotNoEndLine() {
        let timeline = states(to: 3600) { second in
            second < 30
                ? self.cursor(at: second, assertion: true, hook: .working, hookAt: 0, writeAt: min(second, 20))
                : self.cursor(at: second, hook: .idle, hookAt: 30, writeAt: 20)
        }
        XCTAssertEqual(Array(timeline[0..<30]), Array(repeating: .working, count: 30))
        XCTAssertEqual(Array(timeline[30...]), Array(repeating: .idle, count: 3571))
        // The transcript is written a few seconds after the stop.
        let late = states(to: 600) { second in self.cursor(at: second, hook: .idle, hookAt: 30, writeAt: min(second, 39)) }
        XCTAssertEqual(Array(late[40...]), Array(repeating: .idle, count: 561))
    }

    /// Cursor writes an end line after all: the transcript says idle, with
    /// the hooks and without.
    func testATurnWithAnEndLineIsIdleWithAndWithoutTheHooks() {
        for hook in [ReportedState.idle, nil] {
            let timeline = states(to: 600) { second in self.cursor(.idle, at: second, hook: hook, hookAt: 0, writeAt: 1) }
            XCTAssertEqual(timeline, Array(repeating: .idle, count: 601), "\(String(describing: hook))")
        }
    }

    /// Without the hooks, an open turn with no assertion is a wait, as before.
    func testWithoutTheHooksAnOpenTurnWithNoAssertionIsAWait() {
        let timeline = states(to: 600) { second in self.cursor(at: second, writeAt: 20) }
        XCTAssertEqual(Array(timeline[0..<15]), Array(repeating: .working, count: 15))
        XCTAssertEqual(Array(timeline[15...]), Array(repeating: .waitingForUser, count: 586))
    }

    /// A stop that is older than the last write is the stop of an earlier
    /// turn: the turn in progress began with an event that got lost.
    func testAStopHookFromBeforeTheLastWriteEndsNothing() {
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(cursor(at: 200, hook: .idle, hookAt: 30, writeAt: 100)))
        XCTAssertTrue(CursorApprovalRule.signs(of: cursor(at: 200, hook: .idle, hookAt: 30, writeAt: 100)))
        let asks = states(to: 200) { second in self.cursor(at: second, hook: .idle, hookAt: -100, writeAt: 0) }
        XCTAssertEqual(asks.firstIndex(of: .waitingForUser), 15)
        let works = states(to: 200) { second in self.cursor(at: second, assertion: true, hook: .idle, hookAt: -100, writeAt: 0) }
        XCTAssertEqual(works, Array(repeating: .working, count: 201))
        // The stop of one conversation while another holds the assertion
        // or runs a command.
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(cursor(at: 40, assertion: true, hook: .idle, hookAt: 30, writeAt: 20)))
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(cursor(at: 40, commands: 1, hook: .idle, hookAt: 30, writeAt: 20)))
        // A turn that began after the stop.
        var began = cursor(at: 40, hook: .idle, hookAt: 30, writeAt: 35)
        began.reported?.since = at(35)
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(began))
        XCTAssertTrue(CursorApprovalRule.endedByStopHook(cursor(at: 40, hook: .idle, hookAt: 30, writeAt: 20)))
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(cursor(at: 40, hook: .working, hookAt: 30, writeAt: 20)))
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(cursor(.idle, at: 40, hook: .idle, hookAt: 30, writeAt: 20)))
    }

    /// The collector set each stop against its own conversation already.
    /// The turn that is still open is the turn of another conversation,
    /// and the stop of the first one does not end it.
    func testAStopThatWasSetAgainstItsOwnConversationEndsNoOtherOne() {
        var other = cursor(at: 40, hook: .idle, hookAt: 30, writeAt: 20)
        other.hookStateBySession = true
        XCTAssertFalse(CursorApprovalRule.endedByStopHook(other))
        XCTAssertTrue(CursorApprovalRule.signs(of: other))
        let timeline = states(to: 3600) { second in
            var evidence = self.cursor(at: second, hook: second < 30 ? nil : .idle, hookAt: 30, writeAt: 20)
            evidence.hookStateBySession = second >= 30
            return evidence
        }
        XCTAssertEqual(Array(timeline[15...]), Array(repeating: .waitingForUser, count: 3586), "The approval of the other conversation is still pending")

        XCTAssertTrue(CursorApprovalRule.stopEnds(turnSince: at(0), lastWrite: at(20), stop: at(30)))
        XCTAssertTrue(CursorApprovalRule.stopEnds(turnSince: nil, lastWrite: at(45), stop: at(30)), "The transcript lags behind the stop")
        XCTAssertFalse(CursorApprovalRule.stopEnds(turnSince: nil, lastWrite: at(46), stop: at(30)))
        XCTAssertFalse(CursorApprovalRule.stopEnds(turnSince: at(31), lastWrite: at(31), stop: at(30)))
        XCTAssertTrue(CursorApprovalRule.stopEnds(turnSince: at(0), lastWrite: nil, stop: at(30)))
    }

    /// The assertion goes at the end of a turn, and the Mac sleeps for an
    /// hour 5 seconds later, before the end line is written. The settle
    /// time ran out in the sleep, and Cursor read as waiting on wake.
    func testTheSettleTimeDoesNotRunWhileTheMacSleeps() {
        var memory: [ProcessIdentity: AgentMemory] = [:]
        var states: [TimeInterval: WorkState] = [:]
        for second in Array(stride(from: 0.0, through: 5, by: 1)) + Array(stride(from: 3605.0, through: 3620, by: 1)) {
            if second == 3605 { memory = memory.mapValues { $0.shifted(by: 3600) } }
            let frame = EvidenceFrame(at: at(second), agents: [cursor(at: second)])
            let (readings, next) = VerdictRules.readings(for: frame, memory: memory, settings: DetectionSettings())
            memory = next
            states[second] = readings[0].verdict.state
        }
        XCTAssertEqual(states[3605], .working)
        XCTAssertEqual(states[3614], .working)
        XCTAssertEqual(states[3615], .waitingForUser, "15 seconds awake with the signs")
    }

    func testTheUsersRuleStands() {
        var settings = DetectionSettings()
        settings.agentRules["cursor-desktop"] = .ignore
        var memory = AgentMemory()
        var verdict = AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
        for second in 0...20 {
            (verdict, memory) = VerdictRules.verdict(for: cursor(at: TimeInterval(second)), memory: memory, settings: settings, now: at(TimeInterval(second)))
        }
        XCTAssertEqual(verdict.reason, .ignoredByRule)
    }

    func testTheRecordingKeepsTheInputsAndTheReason() throws {
        let evidence = cursor(at: 5)
        let data = try LabFormat.encoder().encode(evidence)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""src":"cursorTranscript""#) || text.contains(#""source":"cursorTranscript""#), text)
        XCTAssertFalse(text.contains("pwr"), "No assertion: the key is left out")
        XCTAssertFalse(text.contains("cmds"))
        XCTAssertEqual(try LabFormat.decoder().decode(AgentEvidence.self, from: data).reported?.source, .cursorTranscript)
        let held = String(decoding: try LabFormat.encoder().encode(cursor(at: 5, assertion: true, commands: 2)), as: UTF8.self)
        XCTAssertTrue(held.contains(#""pwr":true"#) && held.contains(#""cmds":2"#), held)
        XCTAssertEqual(VerdictReason.awaitsApproval.code, "awaitsApproval")
    }
}
