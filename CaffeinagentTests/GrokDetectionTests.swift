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
    var directories: [Int32: String] = [:]
    func openFilePaths(of pid: Int32) -> [String]? { [] }
    func workingDirectory(of pid: Int32) -> String? { directories[pid] }
}

/// Event lines with the keys of a real Grok Build `events.jsonl`
/// (docs/research/10-grok-build.md) and made-up values.
private enum Event {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func line(_ type: String, at date: Date, _ rest: String = "") -> String {
        "{\"ts\":\"\(formatter.string(from: date))\",\"type\":\"\(type)\"\(rest.isEmpty ? "" : ",")\(rest)}"
    }

    static func started(at date: Date) -> String {
        line("turn_started", at: date, #""session_id":"019f94b8-0000-7000-8000-000000000001","turn_number":0,"model_id":"m","yolo_mode":false,"conversation_message_count":2,"session_relationship":"primary","schema_version":"1.0""#)
    }

    static func ended(at date: Date, outcome: String = "completed") -> String { line("turn_ended", at: date, "\"outcome\":\"\(outcome)\"") }
    static func phase(_ phase: String, at date: Date) -> String { line("phase_changed", at: date, "\"phase\":\"\(phase)\"") }
    static func asked(at date: Date) -> String { line("permission_requested", at: date, #""tool_name":"run_terminal_command""#) }
    static func answered(at date: Date) -> String { line("permission_resolved", at: date, #""tool_name":"run_terminal_command","decision":"allow","wait_ms":3094"#) }
    static func toolStarted(at date: Date) -> String { line("tool_started", at: date, #""tool_name":"run_terminal_command""#) }
    static func toolCompleted(at date: Date) -> String { line("tool_completed", at: date, #""tool_name":"run_terminal_command","duration_ms":10,"outcome":"success""#) }

    static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }
}

final class GrokEventsReaderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_300_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testTheNewestTurnMarkerDecides() {
        let cases: [(name: String, lines: [String], want: GrokTurnState)] = [
            ("no line", [], GrokTurnState()),
            ("only lines of the servers", [Event.line("mcp_init_completed", at: at(0), #""total_servers":2"#)], GrokTurnState()),
            ("a turn began", [Event.started(at: at(1))], GrokTurnState(turn: .running(since: at(1)))),
            ("the answer comes", [Event.started(at: at(1)), Event.line("loop_started", at: at(2), #""loop_index":0"#), Event.phase("streaming_text", at: at(3))],
             GrokTurnState(turn: .running(since: at(1)))),
            ("the turn ended", [Event.started(at: at(1)), Event.phase("streaming_text", at: at(3)), Event.ended(at: at(4))], GrokTurnState(turn: .ended(at: at(4)))),
            ("stopped by the user", [Event.started(at: at(1)), Event.ended(at: at(4), outcome: "cancelled")], GrokTurnState(turn: .ended(at: at(4)))),
            ("the next turn", [Event.started(at: at(1)), Event.ended(at: at(4)), Event.started(at: at(9))], GrokTurnState(turn: .running(since: at(9)))),
            ("a request with no answer", [Event.started(at: at(1)), Event.toolStarted(at: at(2)), Event.phase("permission_prompt", at: at(2)), Event.asked(at: at(2))],
             GrokTurnState(turn: .running(since: at(1)), askedAt: at(2))),
            ("the mode was switched while it asks", [Event.started(at: at(1)), Event.asked(at: at(2)), Event.line("yolo_toggled", at: at(3), #""enabled":true"#)],
             GrokTurnState(turn: .running(since: at(1)), askedAt: at(2))),
            ("the request was answered", [Event.started(at: at(1)), Event.asked(at: at(2)), Event.answered(at: at(5)), Event.phase("tool_execution", at: at(5))],
             GrokTurnState(turn: .running(since: at(1)))),
            ("the second request is open", [Event.started(at: at(1)), Event.asked(at: at(2)), Event.answered(at: at(5)), Event.asked(at: at(6))],
             GrokTurnState(turn: .running(since: at(1)), askedAt: at(6))),
            ("a request of the turn before", [Event.started(at: at(1)), Event.asked(at: at(2)), Event.ended(at: at(3)), Event.started(at: at(9))],
             GrokTurnState(turn: .running(since: at(9)))),
            ("an open request and the turn ended", [Event.started(at: at(1)), Event.asked(at: at(2)), Event.ended(at: at(3), outcome: "cancelled")],
             GrokTurnState(turn: .ended(at: at(3)))),
        ]
        for c in cases {
            XCTAssertEqual(GrokEventsReader.parseTail(Event.text(c.lines)), c.want, c.name)
        }
    }

    func testALastLineThatIsCutOffIsPassedOver() {
        let cut = Event.text([Event.started(at: at(1))]) + #"{"ts":"2026-10-08T10:00:05.000Z","type":"turn_en"#
        XCTAssertEqual(GrokEventsReader.parseTail(cut), GrokTurnState(turn: .running(since: at(1))))
        let middle = Data(Event.text([Event.started(at: at(1)), Event.ended(at: at(4))]).utf8).dropFirst(20)
        XCTAssertEqual(GrokEventsReader.parseTail(Data(middle), fromStart: false), GrokTurnState(turn: .ended(at: at(4))))
        XCTAssertEqual(GrokEventsReader.parseTail(Data(Event.text([Event.started(at: at(1))]).utf8).dropFirst(20), fromStart: false), GrokTurnState(), "The first line is a part of a line")
        // Text that only names a marker is no marker.
        XCTAssertEqual(GrokEventsReader.parseTail(Event.text([Event.line("tool_started", at: at(1), #""tool_name":"turn_ended""#)])), GrokTurnState())
    }

    /// A long answer is thousands of `phase_changed` lines after the start.
    func testAStartThatIsFarFromTheEndIsStillFound() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grok-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let phases = (0..<3000).map { Event.phase("streaming_text", at: at(2 + TimeInterval($0) / 100)) }
        let text = Event.text([Event.started(at: at(1)), Event.asked(at: at(1)), Event.answered(at: at(1))] + phases)
        XCTAssertGreaterThan(text.utf8.count, Int(GrokEventsReader.tailSteps[0]))
        try Data(text.utf8).write(to: url)
        XCTAssertEqual(GrokEventsReader.parseTail(of: url), GrokTurnState(turn: .running(since: at(1))))
        XCTAssertEqual(GrokEventsReader.parseTail(of: url.appendingPathExtension("none")), GrokTurnState())
    }

    func testLogsOfAWorkingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grok-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = GrokEventsReader(sessionsDirectory: root)
        func write(_ path: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: url)
        }
        try write("%2FUsers%2Fme%2Fmy%20app/019f-a/events.jsonl")
        try write("%2FUsers%2Fme%2Fmy%20app/019f-b/events.jsonl")
        try write("%2FUsers%2Fme%2Fmy%20app/019f-c/chat_history.jsonl")
        try write("%2FUsers%2Fme%2Fmy%20app/prompt_history.jsonl")
        try write("%2FUsers%2Fme%2Fother/019f-d/events.jsonl")
        try write("session_search.sqlite")
        XCTAssertEqual(Set(reader.logs(forDirectory: "/Users/me/my app").map(\.sessionID)), ["019f-a", "019f-b"])
        XCTAssertEqual(reader.logs(forDirectory: "/Users/me/other").map(\.url.path), [root.appendingPathComponent("%2FUsers%2Fme%2Fother/019f-d/events.jsonl").path])
        XCTAssertEqual(reader.logs(forDirectory: "/Users/me"), [])
        XCTAssertEqual(GrokEventsReader(sessionsDirectory: root.appendingPathComponent("none")).logs(forDirectory: "/Users/me/other"), [])
    }

    func testSummary() {
        let now = at(100)
        func report(_ readings: [GrokTurnState]) -> StateReport? { GrokSummary.report(of: readings, now: now) }
        let running = GrokTurnState(turn: .running(since: at(10)))
        XCTAssertNil(report([]), "No log: the session has had no prompt")
        XCTAssertNil(report([GrokTurnState()]), "A log that was not understood says nothing")
        XCTAssertEqual(report([running]), StateReport(state: .working, since: at(10), observedAt: now, source: .grokEvents, detail: "in a turn"))
        XCTAssertEqual(report([GrokTurnState(turn: .ended(at: at(50)))]), StateReport(state: .idle, since: at(50), observedAt: now, source: .grokEvents, detail: nil))
        XCTAssertEqual(report([GrokTurnState(turn: .ended(at: at(50))), GrokTurnState(turn: .ended(at: at(70)))])?.since, at(70))
        XCTAssertEqual(report([GrokTurnState(turn: .ended(at: at(50))), running])?.state, .working)
        XCTAssertEqual(report([GrokTurnState(), running])?.state, .working)
        XCTAssertNil(report([GrokTurnState(), GrokTurnState(turn: .ended(at: at(50)))]), "Idle is said only when every log was understood")
        // Grok Build asks itself first, for up to 12.6 seconds as measured.
        XCTAssertEqual(report([GrokTurnState(turn: .running(since: at(10)), askedAt: at(100 - 14.9))])?.state, .working)
        XCTAssertEqual(report([GrokTurnState(turn: .running(since: at(10)), askedAt: at(85))]),
                       StateReport(state: .waitingForUser, since: at(85), observedAt: now, source: .grokEvents, detail: nil))
        XCTAssertEqual(report([GrokTurnState(turn: .running(since: at(10)), askedAt: at(85)), running])?.state, .working, "Another session works")
        XCTAssertEqual(report([GrokTurnState(turn: .running(since: at(10)), askedAt: at(200))])?.state, .working, "A time from ahead of the clock")
    }
}

final class GrokCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow
    private let catalog = AgentCatalog.standard
    private let binary = "/Users/me/.grok/downloads/grok-macos-aarch64"

    func testMatch() {
        let cases: [(name: String, path: String, args: [String], role: AgentRole?)] = [
            ("the TUI", binary, ["/Users/me/.grok/bin/grok"], .session),
            ("the TUI with a prompt", binary, ["grok", "fix the bug"], .session),
            ("the other name of the binary", binary, ["/Users/me/.grok/bin/agent"], .session),
            ("a headless run", binary, ["grok", "--always-approve", "-p", "say hi"], .session),
            ("the headless command", binary, ["grok", "agent", "--prompt-file", "p.md"], .session),
            ("installed in another place", "/opt/homebrew/bin/grok", ["grok"], .session),
            ("its help", binary, ["grok", "help"], nil),
            ("the MCP settings", binary, ["grok", "mcp", "list"], nil),
            ("what it finds", binary, ["grok", "inspect", "--json"], nil),
            ("an update", binary, ["grok", "update"], nil),
            ("a command it wraps", binary, ["grok", "wrap", "vim"], nil),
            ("the login", binary, ["/Users/me/.grok/bin/agent", "login"], nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: c.path, args: c.args), userNames: [])
            XCTAssertEqual(match?.role, c.role, c.name)
            if c.role != nil { XCTAssertEqual(match?.definition.id, "grok", c.name) }
        }
        let definition = catalog.definitions.first { $0.id == AgentCatalog.grokID }
        XCTAssertEqual(definition?.displayName, "Grok Build")
        XCTAssertEqual(definition?.level, .state)
        XCTAssertEqual(definition?.kind, .cli)
        XCTAssertTrue(catalog.cliNames.contains("grok"))
        XCTAssertEqual(AgentCatalog.version, 7)
    }

    /// A tool call is a child of the one process, and a Claude Code that
    /// Grok Build wraps is an agent of its own.
    func testOneSessionIsOneInstanceWithItsCommands() {
        let rows: [Row] = [
            .fixture(700, path: binary, args: ["/Users/me/.grok/bin/grok"]),
            .fixture(710, ppid: 700, path: "/bin/zsh", args: ["zsh", "-c", "sleep 400"]),
            .fixture(711, ppid: 710, path: "/bin/sleep", args: ["sleep", "400"]),
            .fixture(800, path: binary, args: ["grok", "wrap", "claude"]),
            .fixture(810, ppid: 800, path: "/Users/me/.local/share/claude/versions/2.1.289", args: ["claude"]),
        ]
        let instances = catalog.instances(in: rows)
        XCTAssertEqual(instances.map(\.definitionID).sorted(), ["claude", "grok"])
        XCTAssertEqual(instances.first { $0.definitionID == "grok" }?.rows.map(\.pid), [700, 710, 711])
    }
}

final class GrokHookTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private var home: URL!
    private var installer: HookInstaller!
    private let grok = HookCatalog.entry(id: "grok")!
    private let appPath = "/Applications/agent caffeine.app"

    /// The form of a file another tool keeps in `~/.grok/hooks`. The
    /// command is made up.
    private let foreign = """
    {
      "hooks": {
        "SessionStart": [
          {
            "hooks": [
              {
                "command": "sh '/Users/me/.grok/hooks/other-state.sh' session",
                "timeout": 10,
                "type": "command"
              }
            ]
          }
        ]
      }
    }
    """

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".grok/hooks"), withIntermediateDirectories: true)
        try Data(foreign.utf8).write(to: home.appendingPathComponent(".grok/hooks/other.json"))
        installer = HookInstaller(home: home, appPath: appPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var url: URL { installer.configURL(for: grok) }
    private var folder: URL { home.appendingPathComponent(".grok/hooks") }

    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: The table

    func testOnlyEventsThatAnEmptyAnswerDoesNotChangeAreRegistered() {
        XCTAssertEqual(grok.events, ["UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "SessionEnd"])
        // `PreToolUse` can deny a tool, and a subagent that stops does not end the turn.
        for event in ["PreToolUse", "SubagentStop", "SubagentEnd", "SubagentStart", "Notification", "PermissionDenied", "SessionStart", "PreCompact", "PostCompact"] {
            XCTAssertEqual(HookEvents.action(agent: "grok", event: event, notificationType: nil, isSubagent: false), .ignore, event)
        }
        for event in ["UserPromptSubmit", "PostToolUse", "PostToolUseFailure"] {
            XCTAssertEqual(HookEvents.action(agent: "grok", event: event, notificationType: nil, isSubagent: false), .set(.working), event)
        }
        for event in ["Stop", "StopFailure"] {
            XCTAssertEqual(HookEvents.action(agent: "grok", event: event, notificationType: nil, isSubagent: false), .set(.idle), event)
        }
        XCTAssertEqual(HookEvents.action(agent: "grok", event: "SessionEnd", notificationType: nil, isSubagent: false), .end)
        XCTAssertTrue(grok.rules.allSatisfy { $0.matcher == nil }, "Grok Build ignores a matcher on Stop and UserPromptSubmit with a warning")
        XCTAssertEqual(HookEvents.hookAgent(forDefinition: "grok"), "grok")
        XCTAssertFalse(HookEvents.stampedAgents.contains("grok"))
        XCTAssertEqual(grok.displayName, "Grok Build")
        XCTAssertEqual(grok.benefit, "Lets Agent Caffeine see at once when Grok Build starts and stops working")
        XCTAssertEqual(grok.configPath, ".grok/hooks/agent-caffeine.json")
        XCTAssertEqual(installer.displayPath(for: grok), "~/.grok/hooks/agent-caffeine.json")
        XCTAssertFalse(HookCatalog.notConfirmed.contains { $0.agent.contains("Grok") })
    }

    // MARK: The file

    /// The bytes that `grok inspect --json` of Grok Build 0.2.111 was
    /// shown, and listed as six hooks of the user.
    func testTheFileIsOursAloneAndGoesAgain() throws {
        XCTAssertEqual(installer.status(of: grok), .notInstalled)
        try installer.install(grok)
        XCTAssertEqual(installer.status(of: grok), .installed(version: HookCatalog.version))
        XCTAssertEqual(try names(), ["agent-caffeine.json", "other.json"])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("other.json"), encoding: .utf8), foreign, "The file of the other tool is not touched")
        XCTAssertEqual(installer.record(for: grok)?.createdFile, true)

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Array(root.keys), ["hooks"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(hooks.keys), Set(grok.events))
        for event in grok.events {
            let groups = try XCTUnwrap(hooks[event], event)
            XCTAssertEqual(groups.count, 1, event)
            XCTAssertEqual(Set(groups[0].keys), ["hooks"], "No matcher")
            let handlers = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]], event)
            XCTAssertEqual(handlers.count, 1, event)
            XCTAssertEqual(handlers[0]["type"] as? String, "command", event)
            XCTAssertEqual(handlers[0]["command"] as? String, HookCatalog.command(agent: "grok", event: event, appPath: appPath), event)
            XCTAssertEqual(handlers[0]["timeout"] as? Int, 5, "Grok Build waits 600 seconds for a Stop hook with no timeout")
        }
        let command = HookCatalog.command(agent: "grok", event: "Stop", appPath: appPath)
        XCTAssertEqual(command, "[ -x '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' ] && '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' grok Stop v=1 || true")
        XCTAssertFalse(command.contains("$"), "Grok Build expands $VAR in a command when it loads the file")

        try installer.install(grok)
        XCTAssertEqual(try names(), ["agent-caffeine.json", "other.json"], "The same the second time, and no backup")
        try installer.uninstall(grok)
        XCTAssertEqual(try names(), ["other.json"])
        XCTAssertEqual(installer.status(of: grok), .notInstalled)
        XCTAssertNil(installer.record(for: grok))
        try installer.uninstall(grok)
        XCTAssertEqual(try names(), ["other.json"])
    }

    func testEntriesOfAnotherPathAreOutdatedAndRefreshed() throws {
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(grok)
        XCTAssertEqual(installer.status(of: grok), .outdated)
        try installer.install(grok)
        XCTAssertEqual(installer.status(of: grok), .installed(version: HookCatalog.version))
        // Grok Build reads `*.json` only, so a backup is no second hook file.
        let backups = try names().filter { $0.contains(HookInstaller.backupInfix) }
        XCTAssertEqual(backups.count, 1)
        XCTAssertFalse(backups.contains { $0.hasSuffix(".json") })
        try installer.uninstall(grok)
        XCTAssertEqual(try names(), ["other.json"], "The file we made goes, and its backups with it")
    }

    func testAFileThatIsNotOursIsKept() throws {
        // The user put hooks of their own into our file.
        try installer.install(grok)
        var source = JSONSourceText(Array(try Data(contentsOf: url)))
        let stop = try XCTUnwrap(source.parsed().member("hooks")?.value.member("Stop")?.value)
        source.append(to: stop) { _ in #"{"hooks": [{"type": "command", "command": "say done"}]}"# }
        try Data(source.bytes).write(to: url)
        XCTAssertEqual(installer.status(of: grok), .installed(version: HookCatalog.version))
        try installer.uninstall(grok)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
        XCTAssertEqual(root, ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]])
        XCTAssertEqual(installer.status(of: grok), .notInstalled)

        try Data("{\"hooks\": ".utf8).write(to: url)
        XCTAssertEqual(installer.status(of: grok), .unreadable)
        XCTAssertThrowsError(try installer.install(grok))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{\"hooks\": ")
    }

    func testGrokBuildThatIsNotSetUp() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".grok"))
        XCTAssertEqual(installer.status(of: grok), .configMissing)
        XCTAssertThrowsError(try installer.install(grok)) { XCTAssertEqual($0 as? HookInstallError, .configMissing) }
        // The folder of the hooks is made when it is not there.
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true)
        XCTAssertEqual(installer.status(of: grok), .notInstalled)
        try installer.install(grok)
        XCTAssertEqual(try names(), ["agent-caffeine.json"])
    }

    // MARK: The command

    private var chain: [Row] {
        [
            .fixture(720, ppid: 700, path: "/bin/sh", args: ["sh", "-c", "hook"]),
            .fixture(700, ppid: 600, path: "/Users/me/.grok/downloads/grok-macos-aarch64", args: ["/Users/me/.grok/bin/grok"]),
            .fixture(600, path: "/bin/zsh", args: ["-zsh"]),
        ]
    }

    func testTheHookLandsOnGrokBuildAndAReplayedClaudeHookOnNothing() {
        XCTAssertEqual(HookCommand.agentProcess(in: chain, hookAgent: "grok")?.pid, 700)
        // Grok Build runs the hooks of ~/.claude/settings.json and of
        // ~/.cursor/hooks.json too: no Claude Code and no Cursor is above them.
        XCTAssertNil(HookCommand.agentProcess(in: chain, hookAgent: "claude"))
        XCTAssertNil(HookCommand.agentProcess(in: chain, hookAgent: "cursor"))
        // Grok Build in a terminal of Claude Code: the hook is its own.
        var nested = chain
        nested[2] = .fixture(600, path: "/Users/me/.local/share/claude/versions/2.1.289", args: ["claude"])
        XCTAssertEqual(HookCommand.agentProcess(in: nested, hookAgent: "grok")?.pid, 700)
        XCTAssertNil(HookCommand.agentProcess(in: nested, hookAgent: "claude"))
    }

    func testRecordFollowsATurnAndKeepsNothingTheUserTyped() throws {
        let directory = home.appendingPathComponent("states")
        let now = Date(timeIntervalSince1970: 1_791_000_500)
        func record(_ event: String, _ input: String, agent: String = "grok", after seconds: TimeInterval) -> Bool {
            HookCommand.record(agent: agent, event: event, input: Array(input.utf8), chain: chain, directory: directory, now: now.addingTimeInterval(seconds))
        }
        func file() throws -> HookStateFile {
            try JSONDecoder().decode(HookStateFile.self, from: Data(contentsOf: directory.appendingPathComponent("grok-700.json")))
        }
        // The keys of Grok Build's input, in camelCase.
        let prompt = #"{"hookEventName":"user_prompt_submit","sessionId":"s-1","cwd":"/Users/me/private","workspaceRoot":"/Users/me/private","permissionMode":"default","prompt":"my secret words","timestamp":"2026-10-08T12:00:00Z"}"#
        XCTAssertTrue(record("UserPromptSubmit", prompt, after: 0))
        let key = HookStateFile.sessionKey("s-1")
        XCTAssertEqual(try file().sessions[key]?.state, "working")
        let stored = try String(contentsOf: directory.appendingPathComponent("grok-700.json"), encoding: .utf8)
        for secret in ["secret", "private", "s-1"] { XCTAssertFalse(stored.contains(secret), secret) }

        XCTAssertTrue(record("PostToolUse", #"{"hookEventName":"post_tool_use","sessionId":"s-1","toolName":"run_terminal_command","toolResult":"x"}"#, after: 5))
        XCTAssertEqual(try file().sessions[key]?.event, "PostToolUse")
        XCTAssertTrue(record("Stop", #"{"hookEventName":"stop","sessionId":"s-1","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"done"}"#, after: 9))
        XCTAssertEqual(try file().sessions[key]?.state, "idle")
        XCTAssertTrue(record("StopFailure", #"{"hookEventName":"stop_failure","sessionId":"s-1","error":"rate_limit"}"#, after: 20))
        XCTAssertEqual(try file().sessions[key]?.state, "idle")

        // Never recorded: an event that is not in the table, and the
        // hooks of Claude Code and Cursor that Grok Build replays.
        XCTAssertFalse(record("PreToolUse", #"{"sessionId":"s-1"}"#, after: 21))
        XCTAssertFalse(record("SubagentStop", #"{"sessionId":"s-1"}"#, after: 21))
        XCTAssertFalse(record("UserPromptSubmit", #"{"sessionId":"s-1"}"#, agent: "claude", after: 21))
        XCTAssertFalse(record("PreToolUse", #"{"sessionId":"s-1"}"#, agent: "claude", after: 21))
        XCTAssertFalse(record("stop", #"{"sessionId":"s-1"}"#, agent: "cursor", after: 21))
        XCTAssertEqual(try file().sessions[key]?.state, "idle")

        XCTAssertTrue(record("SessionEnd", #"{"hookEventName":"session_end","sessionId":"s-1"}"#, after: 30))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }, [], "The last session ended")
    }
}

final class GrokTimelineTests: XCTestCase {
    typealias Row = ProcessInfoRow

    /// A whole second: a file keeps its write time less exactly than a `Date`.
    private let base = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var processStart: TimeInterval { base.timeIntervalSince1970 - 600 }
    private let binary = "/Users/me/.grok/downloads/grok-macos-aarch64"
    private let project = "/Users/me/project"
    private let sessionA = "019f94b8-0000-7000-8000-000000000001"
    private let sessionB = "019f94b8-0000-7000-8000-000000000002"

    private var root: URL!
    private var census: FakeCensus!
    private var files: FakeOpenFiles!
    private var collector: EvidenceCollector!
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

    private var hooks: URL { root.appendingPathComponent("hooks") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        census = FakeCensus()
        files = FakeOpenFiles()
        makeCollector(hooks: false)
        census.rows = [grok(700)]
        files.directories = [700: project]
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCollector(hooks on: Bool) {
        var sources = EvidenceCollector.Sources(census: census, assertions: FakeAssertions(), power: FakePower(), openFiles: files)
        sources.grokEvents = GrokEventsReader(sessionsDirectory: root.appendingPathComponent("sessions"))
        if on { sources.hookDirectory = hooks }
        sources.now = { [unowned self] in self.base.addingTimeInterval(self.seconds) }
        collector = EvidenceCollector(sources: sources)
    }

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    private func grok(_ pid: Int32, cpu: TimeInterval = 0) -> Row {
        .fixture(pid, start: processStart, path: binary, args: ["/Users/me/.grok/bin/grok"], cpu: cpu)
    }

    /// The shell of a tool call with a command below it that uses no CPU.
    private func command(below pid: Int32) -> [Row] {
        [
            .fixture(pid + 10, ppid: pid, start: processStart + 500, path: "/bin/zsh", args: ["zsh", "-c", "sleep 400"]),
            .fixture(pid + 11, ppid: pid + 10, start: processStart + 500, path: "/bin/sleep", args: ["sleep", "400"]),
        ]
    }

    private func write(_ lines: [String], session: String, at seconds: TimeInterval) throws {
        let url = root.appendingPathComponent("sessions/%2FUsers%2Fme%2Fproject/\(session)/events.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Event.text(lines).utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: at(seconds)], ofItemAtPath: url.path)
    }

    private func hook(_ event: String, pid: Int32 = 700, session: String? = nil, at seconds: TimeInterval) {
        let chain: [Row] = [.fixture(pid + 20, ppid: pid, path: "/bin/sh", args: ["sh", "-c", "hook"]), grok(pid)]
        let input = "{\"hookEventName\":\"x\",\"sessionId\":\"\(session ?? sessionA)\"}"
        XCTAssertTrue(HookCommand.record(agent: "grok", event: event, input: Array(input.utf8), chain: chain, directory: hooks, now: at(seconds)), event)
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
    private func run(_ range: ClosedRange<Int>, pid: Int32 = 700, check: ((Step, Int) -> Void)? = nil) -> Step {
        var last: Step?
        for second in range {
            let step = step(TimeInterval(second), pid: pid)
            check?(step, second)
            last = step
        }
        return last!
    }

    /// The log alone, with no hooks: a prompt, a tool call that is quiet
    /// for 400 seconds, and the end.
    func testAPromptAQuietToolCallAndTheEnd() throws {
        let open = run(0...9)
        XCTAssertEqual(open.evidence?.agentID, "grok")
        XCTAssertEqual(open.evidence?.displayName, "Grok Build")
        XCTAssertEqual(open.evidence?.level, .activity, "No prompt yet: no log, and the signs of activity decide as before")
        XCTAssertNil(open.evidence?.reported)
        XCTAssertEqual(open.reading?.verdict.state, .idle)
        XCTAssertNil(open.reading?.turn)

        var lines = [Event.started(at: at(10)), Event.phase("waiting_for_model", at: at(10)), Event.phase("streaming_text", at: at(12)),
                     Event.toolStarted(at: at(13)), Event.asked(at: at(13)), Event.answered(at: at(16)), Event.phase("tool_execution", at: at(16))]
        try write(lines, session: sessionA, at: 16)
        census.rows = [grok(700)] + command(below: 700)
        // The folder of the first session is new, and is found by the next listing.
        let found = run(10...15)
        XCTAssertEqual(found.evidence?.level, .state)
        XCTAssertEqual(found.evidence?.reported, StateReport(state: .working, since: at(10), observedAt: at(15), source: .grokEvents, detail: "in a turn"))
        XCTAssertEqual(found.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy))
        XCTAssertEqual(found.reading?.turn, AgentTurn(state: .working, since: at(10)))
        XCTAssertTrue(found.watched.contains { $0.hasSuffix("/\(sessionA)/events.jsonl") }, "A write to the log brings the next sample at once")

        // No write, no CPU, no event for 400 seconds.
        run(16...416) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)")
            XCTAssertEqual(step.reading?.turn, AgentTurn(state: .working, since: self.at(10)), "\(second)")
            XCTAssertEqual(step.evidence?.childCommands, 1, "\(second)")
        }
        XCTAssertTrue(told.isEmpty)

        lines += [Event.toolCompleted(at: at(417)), Event.phase("streaming_text", at: at(417)), Event.ended(at: at(417))]
        try write(lines, session: sessionA, at: 417)
        census.rows = [grok(700)]
        let ended = step(417)
        XCTAssertEqual(ended.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        XCTAssertEqual(ended.reading?.turn, AgentTurn(state: .idle))
        run(418...500) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
        XCTAssertEqual(told.first?.notice.sessions.first?.workedFor ?? 0, 407, accuracy: 0.5)
    }

    /// A request that stays open is a wait for the user. One that Grok
    /// Build answers itself within the settle time is none.
    func testARequestThatStaysOpenIsAWait() throws {
        var lines = [Event.started(at: at(0)), Event.toolStarted(at: at(2)), Event.asked(at: at(2)), Event.answered(at: at(5)),
                     Event.toolCompleted(at: at(6)), Event.toolStarted(at: at(20)), Event.asked(at: at(20))]
        try write(lines, session: sessionA, at: 20)
        run(0...34) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        XCTAssertTrue(told.isEmpty)
        let waits = run(35...200) { step, second in
            XCTAssertEqual(step.reading?.verdict, AgentVerdict(state: .waitingForUser, confidence: .reported, reason: .asksPermission), "\(second)")
            XCTAssertEqual(step.reading?.turn?.state, .waitingForUser, "\(second)")
        }
        XCTAssertEqual(waits.evidence?.reported?.since, at(20))
        XCTAssertEqual(told.map(\.notice.kind), [.waiting])

        lines += [Event.answered(at: at(201)), Event.phase("tool_execution", at: at(201))]
        try write(lines, session: sessionA, at: 201)
        run(201...220) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        lines += [Event.toolCompleted(at: at(221)), Event.ended(at: at(221))]
        try write(lines, session: sessionA, at: 221)
        XCTAssertEqual(run(221...240).reading?.verdict.state, .idle)
        XCTAssertEqual(told.map(\.notice.kind), [.waiting, .finished])
    }

    /// With the hooks on: the prompt is seen before the log is found, and
    /// Esc, which sends no hook event, ends the turn through the log.
    func testWithTheHooksOnAnInterruptEndsTheTurnAtOnce() throws {
        makeCollector(hooks: true)
        run(0...9)
        hook("UserPromptSubmit", at: 10)
        let prompt = step(10)
        XCTAssertEqual(prompt.evidence?.level, .activity)
        XCTAssertEqual(prompt.evidence?.hookState, .working)
        XCTAssertEqual(prompt.reading?.verdict, AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy), "At once, before the log is found")

        var lines = [Event.started(at: at(10.2)), Event.phase("streaming_text", at: at(12))]
        try write(lines, session: sessionA, at: 12)
        run(11...19) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }
        hook("PostToolUse", at: 20)
        let tool = step(20)
        XCTAssertEqual(tool.evidence?.level, .state)
        XCTAssertEqual(tool.evidence?.hookState, .working)
        run(21...24) { step, second in XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)") }

        lines += [Event.ended(at: at(25), outcome: "cancelled")]
        try write(lines, session: sessionA, at: 25)
        let stopped = step(25)
        XCTAssertNil(stopped.evidence?.hookState, "The log is newer than the hook's working")
        XCTAssertEqual(stopped.reading?.verdict, AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt))
        run(26...120) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])

        // The next prompt: the hook is newer than the end in the log.
        hook("UserPromptSubmit", at: 121)
        XCTAssertEqual(step(121).reading?.verdict.state, .working)
        lines += [Event.started(at: at(121.3)), Event.ended(at: at(130))]
        try write(lines, session: sessionA, at: 130)
        hook("Stop", at: 130.1)
        XCTAssertEqual(step(131).reading?.verdict.state, .idle)
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
        run(132...140)
        XCTAssertEqual(told.map(\.notice.kind), [.finished, .finished])
    }

    /// Two sessions in one folder: nobody can say which log is whose, so
    /// each stands on its hooks alone, as Droid and opencode do.
    func testTwoSessionsInOneFolderStandOnTheirHooks() throws {
        makeCollector(hooks: true)
        census.rows = [grok(700), grok(800)] + command(below: 700)
        files.directories = [700: project, 800: project]
        try write([Event.started(at: at(1))], session: sessionA, at: 1)
        try write([Event.started(at: at(1)), Event.ended(at: at(2))], session: sessionB, at: 2)
        let both = run(0...9)
        XCTAssertEqual(both.evidence?.level, .activity)
        XCTAssertNil(both.evidence?.reported)
        XCTAssertEqual(both.reading?.verdict.state, .idle)

        hook("UserPromptSubmit", at: 10)
        run(10...410) { step, second in
            XCTAssertEqual(step.reading?.verdict.state, .working, "\(second)")
            XCTAssertEqual(step.reading?.turn, AgentTurn(state: .working), "\(second)")
        }
        XCTAssertEqual(step(410, pid: 800).reading?.verdict.state, .idle, "The other session")
        hook("Stop", at: 411)
        run(411...500) { step, second in XCTAssertEqual(step.reading?.verdict.state, .idle, "\(second)") }
        XCTAssertEqual(told.map(\.notice.kind), [.finished])
    }

    /// A Grok Build that was killed leaves a turn that never ends.
    func testALogFromBeforeTheProcessStartedIsNotCounted() throws {
        try write([Event.started(at: at(-900))], session: sessionA, at: -900)
        let old = run(0...9)
        XCTAssertEqual(old.evidence?.level, .activity)
        XCTAssertNil(old.evidence?.reported)
        XCTAssertEqual(old.reading?.verdict.state, .idle)
        // The session is resumed and its log is written again.
        try write([Event.started(at: at(-900)), Event.started(at: at(10))], session: sessionA, at: 10)
        XCTAssertEqual(run(10...15).reading?.verdict.state, .working)
    }

    /// The hooks off and no log, as for a Grok Build with another home
    /// folder: the processor decides, as before.
    func testWithNoLogAndNoHooksTheProcessorDecides() {
        files.directories = [:]
        var cpu: TimeInterval = 0
        let busy = run(0...40) { _, _ in
            cpu += 0.2
            self.census.rows = [self.grok(700, cpu: cpu)]
        }
        XCTAssertEqual(busy.evidence?.level, .activity)
        XCTAssertEqual(busy.reading?.verdict, AgentVerdict(state: .working, confidence: .inferredWeak, reason: .cpuActivity))
        XCTAssertNil(busy.reading?.turn)
    }
}
