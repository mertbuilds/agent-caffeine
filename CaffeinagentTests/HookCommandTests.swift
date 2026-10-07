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
            ("codex", "PreToolUse", nil, false, .set(.working)),
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
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(2), freshness: 60, workingLimit: 1800)?.state, .waitingForUser)
        XCTAssertTrue(record("PostToolUse", #"{"session_id":"s-1"}"#, after: 3))
        XCTAssertFalse(record("Stop", #"{"session_id":"s-1","agent_id":"sub"}"#, after: 4), "A subagent that stops is not the turn")
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(5), freshness: 60, workingLimit: 1800)?.state, .working)
        XCTAssertTrue(record("Stop", #"{"session_id":"s-1"}"#, after: 6))
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(7), freshness: 60, workingLimit: 1800)?.state, .idle)
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

    /// One event whose session id could not be read left a working under
    /// the key of no session. No Stop ends that one.
    func testAnEventWithInputAndNoSessionIDIsDropped() throws {
        XCTAssertTrue(record("UserPromptSubmit", #"{"session_id":"s-1"}"#))
        let cut = #"{"hook_event_name":"PreToolUse","tool_input":{"content":""# + String(repeating: "x", count: 500)
        XCTAssertFalse(record("PreToolUse", cut, after: 1), "The input was cut off before the id")
        XCTAssertFalse(record("PreToolUse", #"{"cwd":"/tmp"}"#, after: 1))
        XCTAssertFalse(record("Stop", #"{"session_id":""}"#, after: 1))
        XCTAssertFalse(record("Notification", #"{"notification_type":"permission_prompt"}"#, after: 1))
        XCTAssertEqual(Array(try file("claude-100.json").sessions.keys), [HookStateFile.sessionKey("s-1")])
        XCTAssertTrue(record("Stop", #"{"session_id":"s-1"}"#, after: 2))
        XCTAssertEqual(try file("claude-100.json").summary(now: now.addingTimeInterval(3), freshness: 60, workingLimit: 1800)?.state, .idle)
    }

    /// No input at all: every event of the process is one session.
    func testEventsWithNoInputAreOneSession() throws {
        XCTAssertTrue(record("UserPromptSubmit", ""))
        XCTAssertEqual(Array(try file("claude-100.json").sessions.keys), ["none"])
        XCTAssertTrue(record("Stop", "", after: 5))
        XCTAssertEqual(try file("claude-100.json").sessions["none"]?.state, "idle")
        XCTAssertTrue(record("SessionEnd", "", after: 6))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("claude-100.json").path))
    }

    /// A working of a session that sends nothing more does not hide the
    /// other sessions of the process for a day.
    func testAWorkingThatNoEventEndsGivesWayAfterTheLimit() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.working), session: "none", event: "PreToolUse", at: now)
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(4000))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(4001), freshness: 60, workingLimit: 1800)?.state, .idle)
        file.apply(.set(.waitingForUser), session: "a", event: "Notification", at: now.addingTimeInterval(4100))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(4101), freshness: 60, workingLimit: 1800)?.state, .waitingForUser)
    }

    // MARK: Input

    private func pipe() throws -> (read: Int32, write: Int32) {
        var ends: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&ends), 0)
        return (ends[0], ends[1])
    }

    private func seconds(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    func testInputIsReadToItsEndAtOnce() throws {
        let ends = try pipe()
        defer { close(ends.read) }
        let text = Array(#"{"session_id":"s-1"}"#.utf8)
        XCTAssertEqual(write(ends.write, text, text.count), text.count)
        close(ends.write)
        var input: [UInt8] = []
        let took = seconds { input = HookCommand.readInput(from: ends.read) }
        XCTAssertEqual(input, text)
        XCTAssertLessThan(took, 0.1, "A closed pipe is no wait")
    }

    /// The agent writes its input 0.4 seconds after it started the hook.
    /// The hook gave up after 0.2 and recorded an event with no session.
    func testInputThatComesLateIsStillRead() throws {
        let ends = try pipe()
        defer { close(ends.read) }
        let text = Array(#"{"session_id":"s-1"}"#.utf8)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            _ = write(ends.write, text, text.count)
            close(ends.write)
        }
        XCTAssertEqual(HookCommand.readInput(from: ends.read), text)
    }

    func testAPipeThatStaysOpenNeverHoldsTheHookForLong() throws {
        XCTAssertLessThanOrEqual(HookCommand.inputWait, 1)
        XCTAssertLessThanOrEqual(HookCommand.inputTotal, 2)
        XCTAssertLessThan(HookCommand.inputTotal, TimeInterval(HookCatalog.timeoutSeconds))
        // Nothing comes.
        let silent = try pipe()
        defer { close(silent.read); close(silent.write) }
        var input: [UInt8] = [1]
        var took = seconds { input = HookCommand.readInput(from: silent.read, wait: 0.2) }
        XCTAssertEqual(input, [])
        XCTAssertLessThan(took, 0.5)
        // The input comes and the pipe is not closed.
        let open = try pipe()
        defer { close(open.read); close(open.write) }
        let text = Array(#"{"session_id":"s-1"}"#.utf8)
        XCTAssertEqual(write(open.write, text, text.count), text.count)
        took = seconds { input = HookCommand.readInput(from: open.read) }
        XCTAssertEqual(input, text)
        XCTAssertLessThan(took, 0.6, "The short wait after a part, not the long one")
        // A writer that never stops is cut at the total.
        let endless = try pipe()
        defer { close(endless.read) }
        let stop = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let byte: [UInt8] = [120]
            while stop.wait(timeout: .now() + 0.02) == .timedOut { _ = write(endless.write, byte, 1) }
            close(endless.write)
        }
        took = seconds { input = HookCommand.readInput(from: endless.read, limit: 8, total: 0.5) }
        stop.signal()
        XCTAssertEqual(input.count, 8, "Kept up to the limit, the rest is read and dropped")
        XCTAssertLessThan(took, 1)
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
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(6), freshness: 60, workingLimit: 1800)?.state, .working)
        file.apply(.set(.waitingForUser), session: "c", event: "PermissionRequest", at: now.addingTimeInterval(7))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(8), freshness: 60, workingLimit: 1800)?.state, .working)
        // The working session sent no event for a minute. It may be in a long
        // tool call, so the idle and the wait of the others do not stand for
        // the process. Its working does, with its real time, and the verdict
        // decides what that is worth.
        for seconds in [65.0, 500, 1800] {
            let standing = file.summary(now: now.addingTimeInterval(seconds), freshness: 60, workingLimit: 1800)
            XCTAssertEqual(standing?.state, .working, "\(seconds)")
            XCTAssertEqual(standing?.at, now, "\(seconds)")
        }
        // After the limit its last event is taken for lost.
        let lost = file.summary(now: now.addingTimeInterval(1801), freshness: 60, workingLimit: 1800)
        XCTAssertEqual(lost?.state, .waitingForUser)
        XCTAssertEqual(lost?.at, now.addingTimeInterval(7))
        // Its Stop ends that.
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(501))
        let later = file.summary(now: now.addingTimeInterval(502), freshness: 60, workingLimit: 1800)
        XCTAssertEqual(later?.state, .waitingForUser)
        XCTAssertEqual(later?.at, now.addingTimeInterval(7))
        // With nothing fresh it is the working that stands, and after the
        // limit the newest, with its real time.
        var old = HookStateFile(agent: "codex", pid: 1, start: 0)
        old.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: now)
        old.apply(.set(.idle), session: "b", event: "Stop", at: now.addingTimeInterval(7))
        XCTAssertEqual(old.summary(now: now.addingTimeInterval(500), freshness: 60, workingLimit: 1800)?.at, now)
        XCTAssertEqual(old.summary(now: now.addingTimeInterval(1801), freshness: 60, workingLimit: 1800)?.at, now.addingTimeInterval(7))
        XCTAssertNil(HookStateFile(agent: "codex", pid: 1, start: 0).summary(now: now, freshness: 60, workingLimit: 1800))
    }

    /// Threads A and B of one Codex engine. A's Stop is fresh, B's last
    /// event was a working more than a minute ago.
    func testAFreshIdleDoesNotHideAnotherSessionThatWorked() {
        var file = HookStateFile(agent: "codex", pid: 1, start: 0)
        file.apply(.set(.working), session: "b", event: "UserPromptSubmit", at: now)
        file.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: now.addingTimeInterval(100))
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(200))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(201), freshness: 60, workingLimit: 1800)?.at, now, "The working of B, too old to beat Codex's own state")
        file.apply(.set(.waitingForUser), session: "a", event: "PermissionRequest", at: now.addingTimeInterval(210))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(211), freshness: 60, workingLimit: 1800)?.at, now)
        file.apply(.end, session: "b", event: "SessionEnd", at: now.addingTimeInterval(220))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(221), freshness: 60, workingLimit: 1800)?.state, .waitingForUser)
    }

    func testAWaitDoesNotAgeOut() {
        var file = HookStateFile(agent: "codex", pid: 1, start: 0)
        file.apply(.set(.waitingForUser), session: "a", event: "PermissionRequest", at: now)
        file.apply(.set(.idle), session: "b", event: "Stop", at: now.addingTimeInterval(3000))
        let later = file.summary(now: now.addingTimeInterval(3010), freshness: 60, workingLimit: 1800)
        XCTAssertEqual(later?.state, .waitingForUser, "An old wait counts before a fresh idle of another session")
        XCTAssertEqual(later?.at, now)
        file.apply(.set(.working), session: "a", event: "PostToolUse", at: now.addingTimeInterval(3020))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(3021), freshness: 60, workingLimit: 1800)?.state, .working, "The next event of the session ends the wait")
    }

    func testAnOlderEventDoesNotReplaceANewerOne() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(2))
        file.apply(.set(.working), session: "a", event: "PostToolUse", at: now)
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
    }

    // MARK: Stamps

    private var opencodeChain: [Row] {
        [.fixture(400, ppid: 50, path: "/Users/me/.opencode/bin/opencode", args: ["opencode"]), .fixture(50, path: "/bin/zsh", args: ["-zsh"])]
    }

    func testInputScannerReadsTheStamp() {
        let input = #"{"session_id":"s-1","seq":12,"ts": 1791375977531 ,"n":3,"inner":{"ts":1,"seq":2}}"#
        let fields = HookInput.topLevelStrings(in: Array(input.utf8))
        XCTAssertEqual(fields, ["session_id": "s-1", "seq": "12", "ts": "1791375977531"])
        XCTAssertEqual(HookStamp(fields: fields), HookStamp(ts: 1_791_375_977_531, seq: 12))
        XCTAssertNil(HookStamp(fields: ["ts": "5"]))
        XCTAssertNil(HookStamp(fields: ["seq": "5"]))
        for text in [#"{"session_id":"s-1","ts":17913"#, #"{"ts":1.5,"seq":-2}"#, #"{"ts":true,"seq":null}"#, #"{"ts":"# + String(repeating: "9", count: 30) + "}"] {
            let found = HookInput.topLevelStrings(in: Array(text.utf8))
            XCTAssertNil(found["ts"], text)
            XCTAssertNil(found["seq"], text)
        }
    }

    /// The hook commands of a busy and of the idle a millisecond later ran
    /// at the same time, and the busy wrote last.
    func testAStampedEventThatIsOlderIsIgnored() {
        var file = HookStateFile(agent: "opencode", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now, stamp: HookStamp(ts: 2001, seq: 8))
        file.apply(.set(.working), session: "a", event: "session.busy", at: now.addingTimeInterval(0.05), stamp: HookStamp(ts: 2000, seq: 7))
        XCTAssertEqual(file.sessions["a"], .init(state: "idle", event: "session.idle", at: now.timeIntervalSince1970, ts: 2001, seq: 8))
        // The next turn is newer and counts, also when its command gives an older time.
        file.apply(.set(.working), session: "a", event: "session.busy", at: now.addingTimeInterval(-1), stamp: HookStamp(ts: 9000, seq: 9))
        XCTAssertEqual(file.sessions["a"]?.state, "working")
    }

    func testEqualTimesAreOrderedByTheNumber() {
        var file = HookStateFile(agent: "opencode", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now, stamp: HookStamp(ts: 2000, seq: 8))
        file.apply(.set(.working), session: "a", event: "session.busy", at: now, stamp: HookStamp(ts: 2000, seq: 7))
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
        file.apply(.set(.working), session: "a", event: "session.busy", at: now, stamp: HookStamp(ts: 2000, seq: 9))
        XCTAssertEqual(file.sessions["a"]?.state, "working")
        XCTAssertTrue(HookStamp(ts: 1, seq: 9) < HookStamp(ts: 2, seq: 1))
    }

    func testEventsWithNoStampAreOrderedAsBefore() {
        // No stamp on either side: the time of the hook command decides.
        var file = HookStateFile(agent: "opencode", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now.addingTimeInterval(2))
        file.apply(.set(.working), session: "a", event: "session.busy", at: now)
        XCTAssertEqual(file.sessions["a"], .init(state: "idle", event: "session.idle", at: now.timeIntervalSince1970 + 2))
        file.apply(.set(.working), session: "a", event: "session.busy", at: now.addingTimeInterval(3))
        XCTAssertEqual(file.sessions["a"]?.state, "working")
        // A stamp on one side only, as when an old plugin is still loaded: the same.
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now.addingTimeInterval(4), stamp: HookStamp(ts: 1, seq: 1))
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
        file.apply(.set(.working), session: "a", event: "session.busy", at: now.addingTimeInterval(5))
        XCTAssertEqual(file.sessions["a"], .init(state: "working", event: "session.busy", at: now.timeIntervalSince1970 + 5))
        // A state file with no stamp is read as it was.
        let old = Data(#"{"v":1,"agent":"opencode","pid":1,"start":0,"sessions":{"a":{"state":"working","event":"session.busy","at":5}}}"#.utf8)
        XCTAssertNil(try? JSONDecoder().decode(HookStateFile.self, from: old).sessions["a"]?.stamp)
        XCTAssertEqual(try? JSONDecoder().decode(HookStateFile.self, from: old).sessions["a"]?.at, 5)
    }

    func testTheStampsOfTwoSessionsDoNotMeet() {
        var file = HookStateFile(agent: "opencode", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now, stamp: HookStamp(ts: 5000, seq: 50))
        file.apply(.set(.working), session: "b", event: "session.busy", at: now, stamp: HookStamp(ts: 1000, seq: 1))
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
        XCTAssertEqual(file.sessions["b"]?.state, "working")
        file.apply(.set(.idle), session: "b", event: "session.idle", at: now, stamp: HookStamp(ts: 1001, seq: 2))
        XCTAssertEqual(file.sessions["b"]?.state, "idle")
    }

    /// A stamp from far ahead was written before the clock was set back.
    func testAStampFromBeforeTheClockWasSetBackIsReplaced() {
        var file = HookStateFile(agent: "opencode", pid: 1, start: 0)
        file.apply(.set(.working), session: "a", event: "session.busy", at: now, stamp: HookStamp(ts: 3_600_000, seq: 1))
        file.apply(.set(.idle), session: "a", event: "session.idle", at: now, stamp: HookStamp(ts: 2000, seq: 2))
        XCTAssertEqual(file.sessions["a"]?.state, "idle")
    }

    func testRecordOrdersOpencodeByItsStamp() throws {
        func opencode(_ event: String, seq: Int, ts: Int, after seconds: TimeInterval) -> Bool {
            record(event, #"{"session_id":"s-1","seq":\#(seq),"ts":\#(ts)}"#, agent: "opencode", chain: opencodeChain, after: seconds)
        }
        XCTAssertTrue(opencode("session.busy", seq: 1, ts: 1000, after: 0))
        // The idle of the turn end lands first, the busy of the last step after it.
        XCTAssertTrue(opencode("session.idle", seq: 3, ts: 15001, after: 15))
        XCTAssertTrue(opencode("session.busy", seq: 2, ts: 15000, after: 15.02))
        let session = try XCTUnwrap(try file("opencode-400.json").sessions[HookStateFile.sessionKey("s-1")])
        XCTAssertEqual(session, .init(state: "idle", event: "session.idle", at: now.timeIntervalSince1970 + 15, ts: 15001, seq: 3))
        // The old plugin sends no stamp: the last writer counts, as before.
        XCTAssertTrue(record("session.busy", #"{"session_id":"s-1"}"#, agent: "opencode", chain: opencodeChain, after: 16))
        XCTAssertEqual(try file("opencode-400.json").sessions[HookStateFile.sessionKey("s-1")]?.state, "working")
    }

    func testAStampIsReadForOpencodeOnly() throws {
        XCTAssertTrue(record("Stop", #"{"session_id":"s-1","seq":9,"ts":9000}"#, after: 2))
        XCTAssertNil(try file("claude-100.json").sessions[HookStateFile.sessionKey("s-1")]?.stamp)
        XCTAssertTrue(record("PostToolUse", #"{"session_id":"s-1","seq":1,"ts":1000}"#, after: 3))
        XCTAssertEqual(try file("claude-100.json").sessions[HookStateFile.sessionKey("s-1")]?.state, "working")
    }

    func testTheHookCommandKnowsWhenItStarted() throws {
        let started = try XCTUnwrap(HookCommand.startTime())
        XCTAssertLessThanOrEqual(started, Date())
        XCTAssertGreaterThan(started, Date().addingTimeInterval(-24 * 3600))
    }

    /// The clock is set back by an hour. The state from before is ahead of
    /// the clock: it is not a fresh state, and the next event replaces it.
    func testClockSetBack() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(3600))
        file.apply(.set(.waitingForUser), session: "b", event: "Notification", at: now.addingTimeInterval(3600))
        let stale = file.summary(now: now, freshness: 60, workingLimit: 1800)
        XCTAssertEqual(stale?.at, now.addingTimeInterval(3600), "The newest, with its real time, for the verdict to refuse")
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(3597), freshness: 60, workingLimit: 1800)?.state, .waitingForUser, "A few seconds ahead is no step")

        file.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: now.addingTimeInterval(10))
        XCTAssertEqual(file.sessions["a"], .init(state: "working", event: "UserPromptSubmit", at: now.timeIntervalSince1970 + 10))
        let fresh = file.summary(now: now.addingTimeInterval(11), freshness: 60, workingLimit: 1800)
        XCTAssertEqual(fresh?.state, .working)
        XCTAssertEqual(fresh?.at, now.addingTimeInterval(10))
        XCTAssertNotNil(file.sessions["b"], "A session from ahead of the clock is not dropped as old")
    }

    /// The clock is set forward by an hour: the events come in order.
    func testClockSetForward() {
        var file = HookStateFile(agent: "claude", pid: 1, start: 0)
        file.apply(.set(.working), session: "a", event: "UserPromptSubmit", at: now)
        file.apply(.set(.idle), session: "a", event: "Stop", at: now.addingTimeInterval(3600))
        XCTAssertEqual(file.summary(now: now.addingTimeInterval(3601), freshness: 60, workingLimit: 1800)?.state, .idle)
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
