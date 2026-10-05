import XCTest

final class HookCommandTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private var directory: URL!
    private let claudeBinary = "/Users/me/.local/share/claude/versions/2.1.289"
    private let codexDesktop = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    private let now = Date(timeIntervalSince1970: 1_791_000_500)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var claudeChain: [Row] {
        [.fixture(300, ppid: 100, path: "/bin/zsh", args: ["zsh", "-c", "hook"]), .fixture(100, ppid: 50, path: claudeBinary, args: ["claude"]), .fixture(50, path: "/bin/zsh", args: ["-zsh"])]
    }

    private func file(_ name: String) throws -> HookStateFile {
        try JSONDecoder().decode(HookStateFile.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
    }

    private func record(_ event: String, _ input: String, agent: String = "claude", chain: [Row]? = nil, after seconds: TimeInterval = 0) -> Bool {
        HookCommand.record(agent: agent, event: event, input: Array(input.utf8), chain: chain ?? claudeChain, directory: directory, now: now.addingTimeInterval(seconds))
    }

    // MARK: Events

    func testEventTable() {
        let cases: [(agent: String, event: String, type: String?, subagent: Bool, expected: HookAction)] = [
            ("claude", "UserPromptSubmit", nil, false, .set(.working)),
            ("claude", "PreToolUse", nil, false, .set(.working)),
            ("claude", "PostToolUse", nil, true, .set(.working)),
            ("claude", "Notification", "permission_prompt", false, .set(.waitingForUser)),
            ("claude", "Notification", "elicitation_dialog", false, .set(.waitingForUser)),
            ("claude", "Notification", "idle_prompt", false, .set(.idle)),
            ("claude", "Notification", "auth_success", false, .ignore),
            ("claude", "Notification", nil, false, .ignore),
            ("claude", "Stop", nil, false, .set(.idle)),
            ("claude", "Stop", nil, true, .ignore),
            ("claude", "SubagentStop", nil, false, .ignore),
            ("claude", "SessionEnd", nil, false, .end),
            ("claude", "SessionEnd", nil, true, .ignore),
            ("codex", "PermissionRequest", nil, false, .set(.waitingForUser)),
            ("codex", "Interrupt", nil, false, .set(.idle)),
            ("codex", "Stop", nil, false, .set(.idle)),
            ("droid", "Notification", "idle_prompt", false, .set(.idle)),
            ("opencode", "session.busy", nil, false, .set(.working)),
            ("opencode", "permission.asked", nil, false, .set(.waitingForUser)),
            ("nobody", "Stop", nil, false, .ignore),
        ]
        for c in cases {
            XCTAssertEqual(HookEvents.action(agent: c.agent, event: c.event, notificationType: c.type, isSubagent: c.subagent), c.expected, "\(c.agent) \(c.event) \(c.type ?? "")")
        }
    }

    func testEveryCatalogEntryHasRulesAndKnownDefinitions() {
        let known = Set(AgentCatalog.standard.definitions.map(\.id))
        for entry in HookCatalog.entries {
            XCTAssertFalse(entry.rules.isEmpty, entry.id)
            XCTAssertFalse(entry.definitionIDs.isEmpty, entry.id)
            XCTAssertTrue(entry.definitionIDs.isSubset(of: known), entry.id)
            XCTAssertFalse(entry.benefit.contains("\u{2014}"))
        }
        XCTAssertEqual(HookEvents.hookAgent(forDefinition: "codex-desktop"), "codex")
        XCTAssertNil(HookEvents.hookAgent(forDefinition: "aider"))
    }

    // MARK: Input

    func testInputScannerReadsTopLevelStringsOnly() {
        let input = #"{"session_id":"s-1","tool_input":{"session_id":"inner","agent_id":"no"},"prompt":"he said \"agent_id\":\"x\" {[","notification_type" : "permission_prompt","n":3}"#
        XCTAssertEqual(HookInput.topLevelStrings(in: Array(input.utf8)), ["session_id": "s-1", "notification_type": "permission_prompt"])
    }

    func testInputScannerSurvivesCutOffAndBadInput() {
        let cut = #"{"session_id":"s-1","tool_response":"aaaa"#
        XCTAssertEqual(HookInput.topLevelStrings(in: Array(cut.utf8)), ["session_id": "s-1"])
        for text in ["", "{", "[1,2", #"{"session_id":"#, #"{"session_id":"abc"#, "\"", "\\", #"{"a":"\"#, "}}}]]"] {
            XCTAssertEqual(HookInput.topLevelStrings(in: Array(text.utf8)), [:], text)
        }
        let long = #"{"session_id":""# + String(repeating: "x", count: 300) + #""}"#
        XCTAssertEqual(HookInput.topLevelStrings(in: Array(long.utf8)), [:], "A value over the limit is left out")
    }

    // MARK: The agent process

    func testNearestAgentProcessOfTheHooksOwnAgent() {
        XCTAssertEqual(HookCommand.agentProcess(in: claudeChain, hookAgent: "claude")?.pid, 100)
        XCTAssertNil(HookCommand.agentProcess(in: claudeChain, hookAgent: "codex"))
        // Droid replays Claude Code's hooks: no Claude Code is above the hook.
        let droid: [Row] = [.fixture(300, ppid: 100, path: "/bin/sh", args: ["sh"]), .fixture(100, path: "/Users/me/.local/bin/droid", args: ["droid"])]
        XCTAssertNil(HookCommand.agentProcess(in: droid, hookAgent: "claude"))
        XCTAssertEqual(HookCommand.agentProcess(in: droid, hookAgent: "droid")?.pid, 100)
        let desktop: [Row] = [.fixture(100, ppid: 9, path: codexDesktop, args: [codexDesktop, "app-server"])]
        XCTAssertEqual(HookCommand.agentProcess(in: desktop, hookAgent: "codex")?.pid, 100)
        // A helper with the agent's name is passed over.
        let helper: [Row] = [.fixture(100, path: claudeBinary, args: ["claude", "daemon", "run"])]
        XCTAssertNil(HookCommand.agentProcess(in: helper, hookAgent: "claude"))
    }

    // MARK: Recording

    func testRecordWritesStateAndNothingTheUserTyped() throws {
        XCTAssertTrue(record("UserPromptSubmit", #"{"session_id":"s-1","prompt":"my secret words","cwd":"/Users/me/private"}"#))
        let written = try String(contentsOf: directory.appendingPathComponent("claude-100.json"), encoding: .utf8)
        for leak in ["secret", "private", "s-1", "Users"] { XCTAssertFalse(written.contains(leak), leak) }
        let file = try file("claude-100.json")
        XCTAssertEqual(file.pid, 100)
        XCTAssertEqual(file.start, claudeChain[1].startTime)
        XCTAssertEqual(file.sessions, [HookStateFile.sessionKey("s-1"): .init(state: "working", event: "UserPromptSubmit", at: now.timeIntervalSince1970)])
    }

    func testRecordFollowsATurn() throws {
        XCTAssertTrue(record("UserPromptSubmit", #"{"session_id":"s-1"}"#))
        XCTAssertTrue(record("Notification", #"{"session_id":"s-1","notification_type":"permission_prompt"}"#, after: 1))
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(2), freshness: 60)?.state, .waitingForUser)
        XCTAssertTrue(record("PostToolUse", #"{"session_id":"s-1"}"#, after: 3))
        XCTAssertFalse(record("Stop", #"{"session_id":"s-1","agent_id":"sub"}"#, after: 4), "A subagent that stops is not the turn")
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(5), freshness: 60)?.state, .working)
        XCTAssertTrue(record("Stop", #"{"session_id":"s-1"}"#, after: 6))
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(7), freshness: 60)?.state, .idle)
        XCTAssertTrue(record("SessionEnd", #"{"session_id":"s-1"}"#, after: 8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("claude-100.json").path))
    }

    func testRecordIgnoresWhatItDoesNotKnow() {
        XCTAssertFalse(record("SubagentStop", #"{"session_id":"s-1"}"#))
        XCTAssertFalse(record("Stop", "{}", agent: "nobody"))
        XCTAssertFalse(record("Stop", "{}", agent: "codex"), "No Codex is above the hook")
        XCTAssertFalse(record("Stop", "{}", chain: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRecordStartsAgainForAReusedPid() throws {
        XCTAssertTrue(record("UserPromptSubmit", #"{"session_id":"old"}"#))
        var chain = claudeChain
        chain[1] = .fixture(100, ppid: 50, start: 1_791_000_400, path: claudeBinary, args: ["claude"])
        XCTAssertTrue(record("Stop", #"{"session_id":"new"}"#, chain: chain, after: 1))
        let file = try file("claude-100.json")
        XCTAssertEqual(file.start, 1_791_000_400)
        XCTAssertEqual(Array(file.sessions.keys), [HookStateFile.sessionKey("new")])
    }

    // MARK: State file

    func testOneWorkingSessionIsNotHiddenByAnotherThatStops() {
        var file = HookStateFile(agent: "codex", pid: 1, start: 0)
        file.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: now)
        file.apply(.set(.idle), session: "b", event: "Stop", at: now.addingTimeInterval(5))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(6), freshness: 60)?.state, .working)
        file.apply(.set(.waitingForUser), session: "c", event: "PermissionRequest", at: now.addingTimeInterval(7))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(8), freshness: 60)?.state, .working)
        // The working session never sent its last event. Once it is old, the fresh ones count.
        let later = file.summary(now: now.addingTimeInterval(65), freshness: 60)
        XCTAssertEqual(later?.state, .waitingForUser)
        XCTAssertEqual(later?.at, now.addingTimeInterval(7))
        // With nothing fresh it is the newest, with its real time.
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(500), freshness: 60)?.at, now.addingTimeInterval(7))
        XCTAssertNil(HookStateFile(agent: "codex", pid: 1, start: 0).summary(now: now, freshness: 60))
    }

    func testAnOlderEventDoesNotReplaceANewerOne() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(2))
        file.apply(.set(.working), session: "a", event: "PostToolUse", at: now)
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
    }

    func testOldAndSurplusSessionsAreDropped() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.working), session: "old", event: "UserPromptSubmit", at: now)
        for index in 0..<(HookStateFile.maxSessions + 5) {
            file.apply(.set(.idle), session: "s\(index)", event: "Stop", at: now.addingTimeInterval(HookStateFile.sessionLifetime + Double(index)))
        }
        XCTAssertNil(file.sessions["old"])
        XCTAssertEqual(file.sessions.count, HookStateFile.maxSessions)
        XCTAssertNil(file.sessions["s0"])
    }

    func testSessionKeyAndDirectory() {
        XCTAssertEqual(HookStateFile.sessionKey(nil), "none")
        XCTAssertEqual(HookStateFile.sessionKey("abc").count, 16)
        XCTAssertEqual(HookStateFile.sessionKey("abc"), HookStateFile.sessionKey("abc"))
        XCTAssertNotEqual(HookStateFile.sessionKey("abc"), HookStateFile.sessionKey("abd"))
        XCTAssertEqual(HookStateFile.directory(environment: [HookStateFile.directoryOverrideKey: "/tmp/x"]).path, "/tmp/x")
        XCTAssertTrue(HookStateFile.directory(environment: [:]).path.hasSuffix("Library/Application Support/com.caffeinagent.app/hooks"))
    }
}
