import XCTest

final class CursorHookTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private var home: URL!
    private var installer: HookInstaller!
    private let cursor = HookCatalog.entry(id: "cursor")!
    private let appPath = "/Applications/agent caffeine.app"
    private let app = "/Applications/Cursor.app/Contents"

    /// The form of a `~/.cursor/hooks.json` that another tool wrote: one
    /// entry per event with a `command` only, the keys in order, and the
    /// version last. The command is made up.
    private let foreign = """
    {
      "hooks": {
        "afterAgentResponse": [
          {
            "command": "/Users/me/.island/bin/island-bridge --source cursor"
          }
        ],
        "beforeShellExecution": [
          {
            "command": "/Users/me/.island/bin/island-bridge --source cursor"
          }
        ],
        "beforeSubmitPrompt": [
          {
            "command": "/Users/me/.island/bin/island-bridge --source cursor"
          }
        ],
        "stop": [
          {
            "command": "/Users/me/.island/bin/island-bridge --source cursor"
          }
        ],
        "subagentStop": [
          {
            "command": "/Users/me/.island/bin/island-bridge --source cursor"
          }
        ]
      },
      "version": 1
    }

    """

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
        installer = HookInstaller(home: home, appPath: appPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var url: URL { installer.configURL(for: cursor) }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: url)
    }

    private func text() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func hooks() throws -> [String: [[String: Any]]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["hooks"] as? [String: [[String: Any]]])
    }

    // MARK: The table

    func testOnlyEventsWhoseAnswerCursorDoesNotReadAreRegistered() {
        XCTAssertEqual(cursor.events, [
            "beforeSubmitPrompt", "afterAgentThought", "afterAgentResponse", "postToolUse", "postToolUseFailure",
            "afterShellExecution", "afterFileEdit", "afterMCPExecution", "stop", "sessionEnd",
        ])
        // An answer Cursor cannot read blocks the action of these.
        for event in ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "subagentStart", "beforeTabFileRead"] {
            XCTAssertFalse(cursor.events.contains(event), event)
            XCTAssertEqual(HookEvents.action(agent: "cursor", event: event, notificationType: nil, isSubagent: false), .ignore, event)
        }
        XCTAssertEqual(HookEvents.action(agent: "cursor", event: "subagentStop", notificationType: nil, isSubagent: false), .ignore)
        let working = ["beforeSubmitPrompt", "afterAgentThought", "afterAgentResponse", "postToolUse", "postToolUseFailure", "afterShellExecution", "afterFileEdit", "afterMCPExecution"]
        for event in working {
            XCTAssertEqual(HookEvents.action(agent: "cursor", event: event, notificationType: nil, isSubagent: false), .set(.working), event)
        }
        XCTAssertEqual(HookEvents.action(agent: "cursor", event: "stop", notificationType: nil, isSubagent: false), .set(.idle))
        XCTAssertEqual(HookEvents.action(agent: "cursor", event: "sessionEnd", notificationType: nil, isSubagent: false), .end)
        XCTAssertFalse(HookEvents.rules["cursor"]?.contains { $0.action == .set(.waitingForUser) } ?? true, "No event exists for an approval")
        XCTAssertEqual(HookEvents.hookAgent(forDefinition: "cursor-desktop"), "cursor")
        XCTAssertNil(HookEvents.hookAgent(forDefinition: "cursor-agent"), "Not confirmed for the CLI")
        XCTAssertEqual(cursor.benefit, "Lets agent caffeine see at once when Cursor starts and stops working")
        XCTAssertEqual(cursor.configPath, ".cursor/hooks.json")
    }

    // MARK: The file

    func testInstallNextToAnotherToolKeepsEveryOtherByteAndUninstallGivesTheSameBytes() throws {
        try write(foreign)
        XCTAssertEqual(installer.status(of: cursor), .notInstalled)
        try installer.install(cursor)
        XCTAssertEqual(installer.status(of: cursor), .installed(version: HookCatalog.version))
        let installed = try text()
        // Every line of the other tool is still there, in its order.
        var rest = Substring(installed)
        for line in foreign.split(separator: "\n") {
            let found = try XCTUnwrap(rest.range(of: line), String(line))
            rest = rest[found.upperBound...]
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(installed.utf8)) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(installed.components(separatedBy: "\"version\"").count, 2, "The version that was there is the only one")
        let all = try hooks()
        for event in cursor.events {
            let entries = try XCTUnwrap(all[event], event)
            let ours = try XCTUnwrap(entries.last, event)
            XCTAssertEqual(ours["command"] as? String, HookCatalog.command(agent: "cursor", event: event, appPath: appPath), event)
            XCTAssertEqual(ours["timeout"] as? Int, 5, event)
            XCTAssertEqual(Set(ours.keys), ["command", "timeout"], "The flat form: no matcher and no inner list")
        }
        XCTAssertEqual(all["stop"]?.count, 2, "After the other tool's entry")
        XCTAssertEqual(all["beforeShellExecution"]?.count, 1, "Never ours")
        XCTAssertEqual(all["subagentStop"]?.count, 1)
        XCTAssertNil(all["preToolUse"])

        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), foreign)
        XCTAssertEqual(installer.status(of: cursor), .notInstalled)
    }

    func testInstallThenUninstallGivesTheSameBytes() throws {
        let cases = [
            foreign,
            "{}", "{}\n", "{\"version\": 1}", "{\n  \"version\": 1\n}\n",
            "{\"version\": 1, \"hooks\": {}}", "{\"hooks\": {\"stop\": []}, \"version\": 1}\n",
            "{\n\t\"version\": 1,\n\t\"hooks\": {\n\t\t\"stop\": [\n\t\t\t{ \"command\": \"other\", \"timeout\": 3 }\n\t\t]\n\t}\n}\n",
            // No version yet: "on" adds one and "off" takes it out.
            "{\"hooks\": {}}", "{\"hooks\": {\"stop\": []}}\n",
            "{\r\n  \"version\": 1,\r\n  \"hooks\": {\r\n    \"sessionEnd\": [\r\n      {\"command\": \"other\"}\r\n    ]\r\n  }\r\n}\r\n",
        ]
        for original in cases {
            try write(original)
            try installer.install(cursor)
            XCTAssertEqual(installer.status(of: cursor), .installed(version: HookCatalog.version), original)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], original)
            XCTAssertEqual(root["version"] as? Int, 1, original)
            try installer.uninstall(cursor)
            XCTAssertEqual(try text(), original)
            XCTAssertEqual(installer.status(of: cursor), .notInstalled, original)
        }
    }

    func testInstallIsTheSameTheSecondTime() throws {
        try write(foreign)
        try installer.install(cursor)
        let once = try text()
        try installer.install(cursor)
        XCTAssertEqual(try text(), once)
        XCTAssertEqual(try hooks()["stop"]?.count, 2)
        try installer.uninstall(cursor)
        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), foreign)
    }

    func testAMissingFileIsMadeAndRemovedAgain() throws {
        try installer.install(cursor)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual(Set(try hooks().keys), Set(cursor.events))
        XCTAssertEqual(installer.record(for: cursor)?.addedVersion, true)
        try installer.uninstall(cursor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAVersionThatWasThereStays() throws {
        try write("{\"version\": 1}")
        try installer.install(cursor)
        XCTAssertNil(installer.record(for: cursor)?.addedVersion)
        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), "{\"version\": 1}")
    }

    /// Another tool's hooks are in a file with no version. "On" adds the
    /// version, and "off" took it out again from under the other tool.
    func testTheVersionWeAddedStaysWhileAnotherToolsHooksAreLeft() throws {
        for original in ["{\"hooks\": {\"stop\": [{\"command\": \"other\"}]}}", "{\n  \"hooks\": {\n    \"stop\": [\n      {\n        \"command\": \"other\"\n      }\n    ]\n  }\n}\n"] {
            try write(original)
            try installer.install(cursor)
            XCTAssertEqual(installer.record(for: cursor)?.addedVersion, true)
            try installer.uninstall(cursor)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary, original)
            XCTAssertEqual(root, ["version": 1, "hooks": ["stop": [["command": "other"]]]], original)
            XCTAssertEqual(installer.status(of: cursor), .notInstalled)
        }
        // The other tool left in the meantime: nothing needs the version.
        try write("{\"hooks\": {\"stop\": [{\"command\": \"other\"}]}}")
        try installer.install(cursor)
        var source = JSONSourceText(Array(try text().utf8))
        let stop = try XCTUnwrap(source.parsed().member("hooks")?.value.member("stop")?.value)
        source.removeChild(at: 0, of: stop)
        try Data(source.bytes).write(to: url)
        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), "{}")
    }

    /// The record of an earlier "on" says that we added the version and
    /// made the file. The user has put a file of their own there since.
    func testAnOldRecordDoesNotClaimAVersionOrAFileThatAreTheUsers() throws {
        try installer.install(cursor)
        XCTAssertEqual(installer.record(for: cursor), HookInstallRecord(emptyBefore: [], createdFile: true, addedVersion: true))
        try write("{\"version\": 1}")
        try installer.install(cursor)
        XCTAssertNil(installer.record(for: cursor)?.addedVersion)
        XCTAssertEqual(installer.record(for: cursor)?.createdFile, false)
        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), "{\"version\": 1}")
        // An update of our own entries keeps what the first "on" recorded.
        try FileManager.default.removeItem(at: url)
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(cursor)
        try installer.install(cursor)
        XCTAssertEqual(installer.record(for: cursor)?.addedVersion, true)
        try installer.uninstall(cursor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEntriesOfAnotherPathAreOutdatedAndRefreshed() throws {
        try write(foreign)
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(cursor)
        XCTAssertEqual(installer.status(of: cursor), .outdated)
        try installer.install(cursor)
        XCTAssertEqual(installer.status(of: cursor), .installed(version: HookCatalog.version))
        XCTAssertEqual(try hooks()["stop"]?.count, 2)
        try installer.uninstall(cursor)
        XCTAssertEqual(try text(), foreign)
    }

    func testABrokenFileAndAnUnknownFormAreNotTouched() throws {
        try write("{\"hooks\": ")
        XCTAssertEqual(installer.status(of: cursor), .unreadable)
        XCTAssertThrowsError(try installer.install(cursor))
        for odd in ["{\"version\": 1, \"hooks\": []}", "{\"version\": 1, \"hooks\": {\"stop\": {}}}", "{\"version\": 1, \"version\": 1}"] {
            try write(odd)
            XCTAssertThrowsError(try installer.install(cursor), odd)
            XCTAssertEqual(try text(), odd)
        }
        try FileManager.default.removeItem(at: home.appendingPathComponent(".cursor"))
        XCTAssertEqual(installer.status(of: cursor), .configMissing)
        XCTAssertThrowsError(try installer.install(cursor)) { XCTAssertEqual($0 as? HookInstallError, .configMissing) }
    }

    func testPreviewShowsTheFlatLines() {
        let preview = HookConfigEditor.preview(for: cursor, appPath: appPath)
        XCTAssertTrue(preview.hasPrefix("hooks.beforeSubmitPrompt:\n{\n  \"command\": "), preview)
        XCTAssertTrue(preview.contains("\"timeout\": 5"))
        XCTAssertFalse(preview.contains("matcher"))
        XCTAssertFalse(preview.contains("\"type\""))
    }

    // MARK: The command

    private var cursorChain: [Row] {
        [
            .fixture(600, ppid: 510, path: "/bin/zsh", args: ["/bin/zsh", "-c", "hook"]),
            .fixture(510, ppid: 500, path: "\(app)/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)", args: ["Cursor Helper (Plugin): extension-host Agents Window [1-1]"]),
            .fixture(500, path: "\(app)/MacOS/Cursor", args: ["\(app)/MacOS/Cursor"]),
        ]
    }

    func testTheHookOfAHelperLandsOnTheMainProcess() {
        XCTAssertEqual(HookCommand.agentProcess(in: cursorChain, hookAgent: "cursor")?.pid, 500)
        // Cursor replays Claude Code's hooks: no Claude Code is above them.
        XCTAssertNil(HookCommand.agentProcess(in: cursorChain, hookAgent: "claude"))
        XCTAssertNil(HookCommand.agentProcess(in: cursorChain, hookAgent: "codex"))
        // Claude Code in the editor's terminal: its hook is its own, and a
        // Cursor hook that an agent CLI there runs is not the editor's.
        let terminal: [Row] = [
            .fixture(700, ppid: 650, path: "/bin/sh", args: ["sh", "-c", "hook"]),
            .fixture(650, ppid: 640, path: "/Users/me/.local/share/claude/versions/2.1.289", args: ["claude"]),
            .fixture(640, ppid: 530, path: "/bin/zsh", args: ["-zsh"]),
            .fixture(530, ppid: 500, path: "\(app)/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper", args: ["Cursor Helper: terminal pty-host"]),
            cursorChain[2],
        ]
        XCTAssertEqual(HookCommand.agentProcess(in: terminal, hookAgent: "claude")?.pid, 650)
        XCTAssertNil(HookCommand.agentProcess(in: terminal, hookAgent: "cursor"))
        var cli = terminal
        cli[1] = .fixture(650, ppid: 640, path: "/Users/me/.local/bin/cursor-agent", args: ["cursor-agent"])
        XCTAssertNil(HookCommand.agentProcess(in: cli, hookAgent: "cursor"))
    }

    func testRecordFollowsATurnByConversationAndKeepsNothingTheUserTyped() throws {
        let directory = home.appendingPathComponent("hooks")
        let now = Date(timeIntervalSince1970: 1_791_000_500)
        func record(_ event: String, _ input: String, agent: String = "cursor", after seconds: TimeInterval) -> Bool {
            HookCommand.record(agent: agent, event: event, input: Array(input.utf8), chain: cursorChain, directory: directory, now: now.addingTimeInterval(seconds))
        }
        func file() throws -> HookStateFile {
            try JSONDecoder().decode(HookStateFile.self, from: Data(contentsOf: directory.appendingPathComponent("cursor-500.json")))
        }
        let input = #"{"conversation_id":"c-1","generation_id":"g-1","hook_event_name":"beforeSubmitPrompt","prompt":"my secret words","user_email":"me@example.com","workspace_roots":["/Users/me/private"]}"#
        XCTAssertTrue(record("beforeSubmitPrompt", input, after: 0))
        XCTAssertEqual(try file().sessions[HookStateFile.sessionKey("c-1")]?.state, "working")
        let stored = try String(contentsOf: directory.appendingPathComponent("cursor-500.json"), encoding: .utf8)
        for secret in ["secret", "example.com", "private", "c-1", "g-1"] { XCTAssertFalse(stored.contains(secret), secret) }

        XCTAssertTrue(record("beforeSubmitPrompt", #"{"conversation_id":"c-2"}"#, after: 1))
        XCTAssertTrue(record("stop", #"{"conversation_id":"c-1","status":"aborted"}"#, after: 2))
        XCTAssertEqual(try file().sessions[HookStateFile.sessionKey("c-1")]?.state, "idle")
        XCTAssertEqual(try file().summary(now: now.addingTimeInterval(3), freshness: 60, workingLimit: 1800)?.state, .working, "The other conversation still works")
        XCTAssertTrue(record("sessionEnd", #"{"conversation_id":"c-2","session_id":"c-2"}"#, after: 4))
        XCTAssertEqual(try file().sessions.count, 1)

        // Never recorded: an event that is not in the table, and a Claude
        // Code hook that Cursor replays.
        XCTAssertFalse(record("beforeShellExecution", #"{"conversation_id":"c-1"}"#, after: 5))
        XCTAssertFalse(record("UserPromptSubmit", #"{"session_id":"c-1"}"#, agent: "claude", after: 5))
        XCTAssertFalse(record("Stop", #"{"session_id":"c-1"}"#, agent: "claude", after: 5))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }, ["cursor-500.json"])
    }
}
