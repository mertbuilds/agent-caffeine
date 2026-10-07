import XCTest

final class HookInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: HookInstaller!
    private let claude = HookCatalog.entry(id: "claude")!
    private let codex = HookCatalog.entry(id: "codex")!
    private let droid = HookCatalog.entry(id: "droid")!
    private let opencode = HookCatalog.entry(id: "opencode")!
    private let pi = HookCatalog.entry(id: "pi")!
    private let appPath = "/Applications/agent caffeine.app"

    /// The form of a settings file that two other tools already wrote into,
    /// with commands that are made up.
    private let foreignClaude = """
    {
      "cleanupPeriodDays": 365,
      "env": {
        "SOME_FLAG": "1"
      },
      "hooks": {
        "Notification": [
          {
            "matcher": "*",
            "hooks": [
              {
                "type": "command",
                "command": "/Users/me/.island/bin/island-bridge --source claude",
                "timeout": 5,
                "async": true
              }
            ]
          }
        ],
        "Stop": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "sh -c 'printf done | \\"$HOME/.term/report.sh\\"'"
              }
            ]
          }
        ]
      },
      "model": "some-model",
      "verbose": false
    }

    """

    private let foreignCodex = """
    {
      "hooks" : {
        "PermissionRequest" : [
          {
            "hooks" : [
              {
                "command" : "'/Users/me/.island/bin/island-bridge' --source codex",
                "timeout" : 7200,
                "type" : "command"
              }
            ]
          }
        ],
        "Stop" : [
          {
            "hooks" : [
              {
                "command" : "'/Users/me/.island/bin/island-bridge' --source codex",
                "timeout" : 5,
                "type" : "command"
              }
            ],
            "matcher" : "*"
          }
        ]
      }
    }
    """

    /// Droid keeps things in `hooks` that are no event lists.
    private let foreignDroid = """
    {
    \t"hooks": {
    \t\t"Notification": [
    \t\t\t{ "hooks": [{ "type": "command", "command": "/Users/me/.island/bin/island-bridge --source droid" }], "matcher": "*" }
    \t\t],
    \t\t"claudeHooksImported": true,
    \t\t"importedClaudeHooks": ["Stop", "Notification"]
    \t}
    }
    """

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        for folder in [".claude", ".codex", ".factory", ".config/opencode", ".pi/agent"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        installer = HookInstaller(home: home, appPath: appPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ text: String, for entry: HookCatalogEntry) throws {
        try Data(text.utf8).write(to: installer.configURL(for: entry))
    }

    private func text(of entry: HookCatalogEntry) throws -> String {
        try String(contentsOf: installer.configURL(for: entry), encoding: .utf8)
    }

    private func json(of entry: HookCatalogEntry) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.configURL(for: entry))) as? NSDictionary)
    }

    private func commands(of entry: HookCatalogEntry, event: String) throws -> [String] {
        let hooks = try XCTUnwrap(json(of: entry)["hooks"] as? [String: Any])
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private func backups(of entry: HookCatalogEntry) -> [String] {
        let folder = installer.configURL(for: entry).deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.contains(HookInstaller.backupInfix) }.sorted()
    }

    // MARK: The command

    func testCommandQuotesAPathWithASpaceAndNeverFails() {
        let command = HookCatalog.command(agent: "claude", event: "Stop", appPath: appPath)
        XCTAssertEqual(command, "[ -x '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' ] && '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' claude Stop v=1 || true")
        XCTAssertEqual(HookCatalog.version(ofCommand: command), HookCatalog.version)
        XCTAssertEqual(HookCatalog.shellQuoted("/a/it's here/x"), "'/a/it'\\''s here/x'")
        XCTAssertNil(HookCatalog.version(ofCommand: "/some/other/tool"))
    }

    /// `sh` runs the command as an agent would. The app is not at the path,
    /// so the command does nothing, prints nothing and still exits 0.
    func testCommandIsSilentWhenTheAppIsGone() throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", HookCatalog.command(agent: "claude", event: "Stop", appPath: home.appendingPathComponent("no app here.app").path)]
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data())
    }

    // MARK: Status

    func testStatusOfEachState() throws {
        XCTAssertEqual(installer.status(of: claude), .notInstalled, "The folder is there and the file is not")
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
        XCTAssertEqual(installer.status(of: codex), .configMissing)
        try write("", for: claude)
        XCTAssertEqual(installer.status(of: claude), .notInstalled)
        try write(foreignClaude, for: claude)
        XCTAssertEqual(installer.status(of: claude), .notInstalled)
        for broken in ["{ not json", "[1, 2]", "{\"hooks\": {},}", "// a comment\n{}", "{\"hooks\": {\"Stop\": [}"] {
            try write(broken, for: claude)
            XCTAssertEqual(installer.status(of: claude), .unreadable, broken)
        }
    }

    // MARK: Install

    func testInstallNextToOtherToolsKeepsEveryOtherByte() throws {
        try write(foreignClaude, for: claude)
        try installer.install(claude)
        XCTAssertEqual(installer.status(of: claude), .installed(version: HookCatalog.version))

        let installed = try text(of: claude)
        // Each line of the old file is still there, in its order.
        var rest = Substring(installed)
        for line in foreignClaude.split(separator: "\n") where !["],", "]", "}"].contains(line.trimmingCharacters(in: .whitespaces)) {
            let range = try XCTUnwrap(rest.range(of: line), String(line))
            rest = rest[range.upperBound...]
        }
        XCTAssertEqual(try commands(of: claude, event: "Notification"), [
            "/Users/me/.island/bin/island-bridge --source claude",
            HookCatalog.command(agent: "claude", event: "Notification", appPath: appPath),
        ], "Ours goes last, so the place of every other entry stays")
        XCTAssertEqual(try commands(of: claude, event: "Stop").count, 2)
        XCTAssertEqual(try commands(of: claude, event: "UserPromptSubmit"), [HookCatalog.command(agent: "claude", event: "UserPromptSubmit", appPath: appPath)])
        let root = try json(of: claude)
        XCTAssertEqual(root["cleanupPeriodDays"] as? Int, 365)
        XCTAssertEqual(root["model"] as? String, "some-model")
        XCTAssertEqual((root["env"] as? [String: String])?["SOME_FLAG"], "1")
        // Key order of the file is kept.
        XCTAssertLessThan(try XCTUnwrap(installed.range(of: "\"env\"")).lowerBound, try XCTUnwrap(installed.range(of: "\"hooks\"")).lowerBound)
        XCTAssertLessThan(try XCTUnwrap(installed.range(of: "\"hooks\"")).lowerBound, try XCTUnwrap(installed.range(of: "\"model\"")).lowerBound)

        XCTAssertEqual(backups(of: claude).count, 1)
        XCTAssertEqual(try String(contentsOf: installer.configURL(for: claude).deletingLastPathComponent().appendingPathComponent(backups(of: claude)[0]), encoding: .utf8), foreignClaude)
    }

    func testInstallThenUninstallGivesTheSameBytes() throws {
        let cases: [(HookCatalogEntry, String)] = [
            (claude, foreignClaude), (codex, foreignCodex), (droid, foreignDroid),
            (claude, "{}"), (claude, "{}\n"), (claude, "{\"model\": \"m\"}"), (claude, "{\n    \"model\": \"m\"\n}\n"),
            (claude, "{\r\n  \"hooks\": {\r\n    \"Stop\": [\r\n      {\"hooks\": [{\"type\": \"command\", \"command\": \"other\"}]}\r\n    ]\r\n  }\r\n}\r\n"),
            // An empty hooks object and empty lists that were there before are the user's.
            (claude, "{\"hooks\": {}}"), (claude, "{\"hooks\": {\"Stop\": []}}"),
            (codex, "{\"hooks\": {\"Stop\": [], \"PreCompact\": []}}\n"),
            (droid, "{\n  \"hooks\": {},\n  \"model\": \"m\"\n}\n"),
            (claude, "{\n  \"hooks\": {\n    \"Stop\": [],\n    \"SessionEnd\": []\n  }\n}\n"),
        ]
        for (entry, original) in cases {
            try write(original, for: entry)
            try installer.install(entry)
            XCTAssertEqual(installer.status(of: entry), .installed(version: HookCatalog.version), original)
            XCTAssertNotEqual(try text(of: entry), original)
            try installer.uninstall(entry)
            XCTAssertEqual(try text(of: entry), original)
            XCTAssertEqual(installer.status(of: entry), .notInstalled)
        }
    }

    func testInstallIntoAMissingAndAnEmptyFile() throws {
        try installer.install(codex)
        XCTAssertEqual(installer.status(of: codex), .installed(version: HookCatalog.version))
        XCTAssertEqual(Set((try json(of: codex)["hooks"] as? [String: Any] ?? [:]).keys), Set(codex.events))
        XCTAssertEqual(backups(of: codex), [], "There was nothing to back up")

        try write("", for: claude)
        try installer.install(claude)
        XCTAssertEqual(installer.status(of: claude), .installed(version: HookCatalog.version))
        try installer.uninstall(claude)
        XCTAssertEqual(try text(of: claude), "", "The file is blank again")
    }

    /// What "on" cannot keep in the file: the bytes of a blank file, and
    /// the space inside an empty object or list. They are in the record,
    /// and "off" puts them back.
    func testOnThenOffGivesTheSameBytesForABlankFileAndForSpacedEmptyContainers() throws {
        let cases: [(HookCatalogEntry, String)] = [
            (claude, ""), (claude, "\n"), (claude, "  \r\n\t"),
            (claude, "{ }"), (claude, "{ }\n"), (claude, "{\n}\n"), (codex, "{\n\n}"),
            (claude, "{\"hooks\": { }}"), (claude, "{\"hooks\": {\n  }\n}\n"),
            (droid, "{\n  \"hooks\": {\n  },\n  \"model\": \"m\"\n}\n"),
            (claude, "{\"hooks\": {\"Stop\": [ ]}}"), (codex, "{\"hooks\": { \"Stop\": [\n    ], \"PreCompact\": [ ] }}\n"),
            (HookCatalog.entry(id: "cursor")!, ""), (HookCatalog.entry(id: "cursor")!, "{ }"),
            (HookCatalog.entry(id: "cursor")!, "{\"version\": 1, \"hooks\": { }}"),
            (HookCatalog.entry(id: "cursor")!, "{\"hooks\": {\"stop\": [ ]}}"),
        ]
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
        for (entry, original) in cases {
            try write(original, for: entry)
            try installer.install(entry)
            XCTAssertEqual(installer.status(of: entry), .installed(version: HookCatalog.version), original.debugDescription)
            try installer.uninstall(entry)
            XCTAssertEqual(try text(of: entry), original, original.debugDescription)
            XCTAssertNil(installer.record(for: entry))
        }
        // Also after an update of our entries in between.
        for original in ["", "{ }", "{\"hooks\": { }}"] {
            try write(original, for: claude)
            try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(claude)
            try installer.install(claude)
            try installer.uninstall(claude)
            XCTAssertEqual(try text(of: claude), original, original.debugDescription)
        }
        // Without the record the file is valid, and not the same.
        try write("{ }", for: claude)
        try installer.install(claude)
        try FileManager.default.removeItem(at: installer.recordsDirectory)
        try installer.uninstall(claude)
        XCTAssertEqual(try text(of: claude), "{}")
        // What the user wrote into the file since stays as it is.
        try write("", for: claude)
        try installer.install(claude)
        var source = JSONSourceText(Array(try text(of: claude).utf8))
        source.append(to: try source.parsed()) { _ in "\"model\": \"m\"" }
        try Data(source.bytes).write(to: installer.configURL(for: claude))
        try installer.uninstall(claude)
        XCTAssertEqual(try json(of: claude), ["model": "m"])
    }

    func testInstallIsRefusedWhenTheAgentIsNotSetUpOrTheFileIsBroken() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
        XCTAssertThrowsError(try installer.install(codex)) { XCTAssertEqual($0 as? HookInstallError, .configMissing) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path))

        for broken in ["{ not json", "[]", "{\"hooks\": [1]}", "{\"hooks\": {\"Stop\": \"text\"}}"] {
            try write(broken, for: claude)
            XCTAssertThrowsError(try installer.install(claude), broken)
            XCTAssertEqual(try text(of: claude), broken, "A file we cannot read is never written")
            XCTAssertEqual(backups(of: claude), [])
        }
        try write("{ not json", for: claude)
        XCTAssertThrowsError(try installer.uninstall(claude)) { XCTAssertEqual($0 as? HookInstallError, .unreadable) }
        XCTAssertEqual(try text(of: claude), "{ not json")
    }

    func testReinstallChangesNothing() throws {
        try write(foreignCodex, for: codex)
        try installer.install(codex)
        let once = try text(of: codex)
        try installer.install(codex)
        XCTAssertEqual(try text(of: codex), once)
        XCTAssertEqual(backups(of: codex).count, 1, "Nothing was written the second time")
        XCTAssertEqual(try commands(of: codex, event: "Stop").filter { $0.contains(HookCatalog.marker) }.count, 1)
    }

    func testDroidKeepsWhatIsNoEventList() throws {
        try write(foreignDroid, for: droid)
        try installer.install(droid)
        let hooks = try XCTUnwrap(json(of: droid)["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["claudeHooksImported"] as? Bool, true)
        XCTAssertEqual(hooks["importedClaudeHooks"] as? [String], ["Stop", "Notification"])
        XCTAssertTrue(try text(of: droid).contains("\n\t\t\"Stop\": ["), "The file's own indentation is used")
    }

    // MARK: Outdated

    func testEntriesWithAnotherPathOrAnOlderVersionAreOutdatedAndRefreshed() throws {
        try write(foreignClaude, for: claude)
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(claude)
        XCTAssertEqual(installer.status(of: claude), .outdated)
        let moved = try text(of: claude)
        XCTAssertEqual(try text(of: claude), moved, "Looking at the status rewrites nothing")

        try installer.install(claude)
        XCTAssertEqual(installer.status(of: claude), .installed(version: HookCatalog.version))
        XCTAssertFalse(try text(of: claude).contains("Downloads"))
        XCTAssertEqual(try commands(of: claude, event: "Stop").filter { $0.contains(HookCatalog.marker) }.count, 1)

        try write(try text(of: claude).replacingOccurrences(of: " v=\(HookCatalog.version) ", with: " v=0 "), for: claude)
        XCTAssertEqual(installer.status(of: claude), .outdated)
        // One event is missing.
        try write(foreignClaude, for: claude)
        try installer.install(claude)
        let text = try text(of: claude)
        var source = JSONSourceText(Array(text.utf8))
        let hooks = try XCTUnwrap(source.parsed().member("hooks")?.value)
        source.removeChild(at: try XCTUnwrap(hooks.members?.firstIndex { $0.key == "SessionEnd" }), of: hooks)
        try Data(source.bytes).write(to: installer.configURL(for: claude))
        XCTAssertEqual(installer.status(of: claude), .outdated)
    }

    // MARK: Uninstall

    func testUninstallTakesOnlyOurHandlerOutOfASharedGroup() throws {
        let ours = HookCatalog.command(agent: "claude", event: "Stop", appPath: appPath)
        let shared = """
        {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "other-tool"}, {"type": "command", "command": \(JSONSourceText.literal(ours))}]}]}}
        """
        try write(shared, for: claude)
        XCTAssertEqual(installer.status(of: claude), .outdated)
        try installer.uninstall(claude)
        XCTAssertEqual(try text(of: claude), "{\"hooks\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"other-tool\"}]}]}}")
    }

    /// Entries of a build that kept no record, or a record that is gone:
    /// only the lists that this run emptied go.
    func testUninstallWithoutARecordRemovesOnlyWhatItEmptied() throws {
        let ours = JSONSourceText.literal(HookCatalog.command(agent: "claude", event: "Stop", appPath: appPath))
        let group = "{\"hooks\": [{\"type\": \"command\", \"command\": \(ours)}]}"
        let cases: [(before: String, after: String)] = [
            ("{\"hooks\": {\"PreCompact\": [], \"Stop\": [\(group)]}}", "{\"hooks\": {\"PreCompact\": []}}"),
            ("{\"hooks\": {\"Stop\": [\(group)]}, \"model\": \"m\"}", "{\"model\": \"m\"}"),
            ("{\"hooks\": {\"Stop\": [\(group)], \"enabled\": true}}", "{\"hooks\": {\"enabled\": true}}"),
            ("{\"hooks\": {\"Stop\": [{\"hooks\": [{\"command\": \"other\"}]}, \(group)], \"PreCompact\": []}}", "{\"hooks\": {\"Stop\": [{\"hooks\": [{\"command\": \"other\"}]}], \"PreCompact\": []}}"),
        ]
        for c in cases {
            try write(c.before, for: claude)
            XCTAssertNil(installer.record(for: claude))
            try installer.uninstall(claude)
            XCTAssertEqual(try text(of: claude), c.after)
        }
        // With nothing of ours in it, nothing is touched.
        for untouched in ["{\"hooks\": {}}", "{\"hooks\": {\"Stop\": []}}"] {
            XCTAssertEqual(try HookConfigEditor.uninstalling(from: Array(untouched.utf8), entry: claude), Array(untouched.utf8))
        }
    }

    /// The record is in our own folder, and the user's file says nothing of it.
    func testTheRecordIsKeptFromOnToOff() throws {
        try write("{\"hooks\": {\"Stop\": []}}", for: claude)
        try installer.install(claude)
        XCTAssertEqual(installer.record(for: claude)?.emptyBefore, [["hooks", "Stop"]])
        XCTAssertTrue(installer.recordsDirectory.path.hasPrefix(home.appendingPathComponent("Library/Application Support/com.caffeinagent.app/").path))
        // On again changes nothing, and the record of the first time stands.
        try installer.install(claude)
        XCTAssertEqual(installer.record(for: claude)?.emptyBefore, [["hooks", "Stop"]])
        // An update of entries from another path keeps the user's empty list too.
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(claude)
        XCTAssertEqual(installer.status(of: claude), .outdated)
        try installer.install(claude)
        XCTAssertEqual(installer.record(for: claude)?.emptyBefore, [["hooks", "Stop"]])
        try installer.uninstall(claude)
        XCTAssertEqual(try text(of: claude), "{\"hooks\": {\"Stop\": []}}")
        XCTAssertNil(installer.record(for: claude))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installer.recordsDirectory.path), [])
    }

    /// A reader takes one of two keys with the same name, and our entries
    /// went into the first.
    func testAKeyThatIsThereTwiceIsRefused() throws {
        let ours = JSONSourceText.literal(HookCatalog.command(agent: "claude", event: "Stop", appPath: appPath))
        let cases = [
            "{\"hooks\": {}, \"hooks\": {\"Stop\": []}}",
            "{\"hooks\": {\"Stop\": [], \"Stop\": []}}",
            "{\"hooks\": {\"Stop\": [{\"hooks\": [{\"command\": \(ours)}]}]}, \"hooks\": {}}",
        ]
        for twice in cases {
            try write(twice, for: claude)
            XCTAssertThrowsError(try installer.install(claude), twice) { XCTAssertEqual($0 as? HookInstallError, .unexpectedShape, twice) }
            XCTAssertEqual(try text(of: claude), twice)
            XCTAssertEqual(backups(of: claude), [])
        }
        try write(cases[0], for: claude)
        XCTAssertEqual(installer.status(of: claude), .unreadable)
        try write(cases[2], for: claude)
        XCTAssertThrowsError(try installer.uninstall(claude)) { XCTAssertEqual($0 as? HookInstallError, .unexpectedShape) }
        XCTAssertEqual(try text(of: claude), cases[2])
    }

    // MARK: A file that we made

    /// The agent had no hooks file. On made it, so off removes it again
    /// and leaves no empty file and no backup behind.
    func testOffRemovesAFileThatOnCreated() throws {
        let url = installer.configURL(for: codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try installer.install(codex)
        XCTAssertEqual(installer.record(for: codex)?.createdFile, true)
        try installer.uninstall(codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(backups(of: codex), [])
        XCTAssertNil(installer.record(for: codex))
        XCTAssertEqual(installer.status(of: codex), .notInstalled)
    }

    /// A hook idle stands at any age, so "off" must not leave one behind.
    func testOffRemovesTheHookStatesOfThatAgentOnly() throws {
        let states = installer.statesDirectory
        XCTAssertTrue(states.path.hasPrefix(home.path))
        XCTAssertEqual(states.lastPathComponent, HookStateFile.directory(environment: [:]).lastPathComponent)
        try FileManager.default.createDirectory(at: states, withIntermediateDirectories: true)
        for name in ["codex-100.json", "codex-200.json", "claude-300.json"] {
            try Data("{}".utf8).write(to: states.appendingPathComponent(name))
        }
        try installer.install(codex)
        try installer.uninstall(codex)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: states.path), ["claude-300.json"])
    }

    func testOffRemovesAFileThatOnCreatedAlsoAfterAnUpdate() throws {
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(codex)
        try installer.install(codex)
        XCTAssertEqual(installer.record(for: codex)?.createdFile, true)
        try installer.uninstall(codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configURL(for: codex).path))
    }

    func testOffKeepsAFileThatHoldsSomethingElse() throws {
        // We made it, and the user or the agent wrote into it later.
        try installer.install(codex)
        var source = JSONSourceText(Array(try text(of: codex).utf8))
        source.append(to: try source.parsed()) { _ in "\"model\": \"m\"" }
        try Data(source.bytes).write(to: installer.configURL(for: codex))
        try installer.uninstall(codex)
        XCTAssertEqual(try json(of: codex) as NSDictionary, ["model": "m"])
        XCTAssertNil(installer.record(for: codex))
    }

    func testOffKeepsAFileThatWasThereBefore() throws {
        for original in ["{}", "{}\n", "{\"hooks\": {}}"] {
            try write(original, for: codex)
            try installer.install(codex)
            XCTAssertEqual(installer.record(for: codex)?.createdFile, false, original)
            try installer.uninstall(codex)
            XCTAssertEqual(try text(of: codex), original)
        }
        // Without the record nobody knows who made the file, so it stays.
        try FileManager.default.removeItem(at: installer.configURL(for: codex))
        try installer.install(codex)
        try FileManager.default.removeItem(at: installer.recordsDirectory)
        try installer.uninstall(codex)
        XCTAssertEqual(try text(of: codex), "{}\n")
    }

    /// Off again with nothing of ours in the file: the file is not ours to remove.
    func testOffWithNothingOfOursKeepsAnEmptyFile() throws {
        try installer.install(codex)
        try write("{}", for: codex)
        try installer.uninstall(codex)
        XCTAssertEqual(try text(of: codex), "{}")
    }

    func testUninstallWithNothingOfOursWritesNothing() throws {
        try write(foreignCodex, for: codex)
        try installer.uninstall(codex)
        XCTAssertEqual(try text(of: codex), foreignCodex)
        XCTAssertEqual(backups(of: codex), [])
        try installer.uninstall(droid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configURL(for: droid).path))
    }

    // MARK: The file shell

    func testALinkStaysALinkAndPermissionsStay() throws {
        let real = home.appendingPathComponent("dotfiles-settings.json")
        try Data(foreignClaude.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: installer.configURL(for: claude), withDestinationURL: real)
        try installer.install(claude)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installer.configURL(for: claude).path), real.path)
        XCTAssertTrue(try String(contentsOf: real, encoding: .utf8).contains(HookCatalog.marker))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int, 0o600)
    }

    /// A link to a file that is gone, as a dotfiles folder that is not
    /// mounted. A regular file took the place of the link.
    func testALinkWhoseDestinationIsGoneIsRefused() throws {
        let missing = home.appendingPathComponent("dotfiles/settings.json")
        for entry in [claude, opencode, pi] {
            let url = installer.configURL(for: entry)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: missing)
            XCTAssertEqual(installer.status(of: entry), .unreadable)
            XCTAssertThrowsError(try installer.install(entry)) { XCTAssertEqual($0 as? HookInstallError, .unreadable) }
            XCTAssertThrowsError(try installer.uninstall(entry)) { XCTAssertEqual($0 as? HookInstallError, .unreadable) }
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), missing.path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
            XCTAssertNil(installer.record(for: entry))
        }
        XCTAssertEqual(backups(of: claude), [])
    }

    func testTwoChangesInOneSecondKeepBothBackups() throws {
        installer.now = { Date(timeIntervalSince1970: 1_791_000_000) }
        try write(foreignCodex, for: codex)
        try installer.install(codex)
        try addModel(to: codex)
        try installer.uninstall(codex)
        let names = backups(of: codex)
        XCTAssertEqual(names.count, 2)
        let folder = installer.configURL(for: codex).deletingLastPathComponent()
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(names[0]), encoding: .utf8), foreignCodex)
    }

    func testOnlyTheNewestBackupsAreKept() throws {
        var second = 0
        installer.now = { second += 1; return Date(timeIntervalSince1970: 1_791_000_000 + Double(second)) }
        try write(foreignCodex, for: codex)
        for _ in 0..<4 {
            try installer.install(codex)
            try addModel(to: codex)
            try installer.uninstall(codex)
        }
        XCTAssertEqual(backups(of: codex).count, HookInstaller.backupsKept)
        XCTAssertEqual(installer.status(of: codex), .notInstalled)
    }

    /// The user or the agent writes a setting into the file while our
    /// entries are in it.
    private func addModel(to entry: HookCatalogEntry) throws {
        var source = JSONSourceText(Array(try text(of: entry).utf8))
        source.append(to: try source.parsed()) { _ in "\"model\": \"m\"" }
        try Data(source.bytes).write(to: installer.configURL(for: entry))
    }

    /// "Off" gave the file back as it was, and the backups of "on" and of
    /// "off" stayed next to it for ever.
    func testOffThatGivesBackTheSameBytesRemovesOurBackups() throws {
        var second = 0
        installer.now = { second += 1; return Date(timeIntervalSince1970: 1_791_000_000 + Double(second)) }
        let folder = installer.configURL(for: claude).deletingLastPathComponent()
        let theirs = folder.appendingPathComponent("settings.json.backup-of-the-user")
        try Data("x".utf8).write(to: theirs)
        for original in [foreignClaude, "", "{ }"] {
            try write(original, for: claude)
            try installer.install(claude)
            XCTAssertEqual(backups(of: claude).count, 1)
            XCTAssertEqual(installer.record(for: claude)?.backups, backups(of: claude))
            try installer.uninstall(claude)
            XCTAssertEqual(try text(of: claude), original)
            XCTAssertEqual(backups(of: claude), [], original.debugDescription)
        }
        // Also with an update of our entries in between.
        try write(foreignClaude, for: claude)
        try HookInstaller(home: home, appPath: "/Users/me/Downloads/agent caffeine.app").install(claude)
        try installer.install(claude)
        XCTAssertEqual(backups(of: claude).count, 2)
        try installer.uninstall(claude)
        XCTAssertEqual(backups(of: claude), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: theirs.path))

        // The file is not what it was: both backups stay.
        try write(foreignClaude, for: claude)
        try installer.install(claude)
        try addModel(to: claude)
        try installer.uninstall(claude)
        XCTAssertEqual(backups(of: claude).count, 2)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(backups(of: claude)[0]), encoding: .utf8), foreignClaude)
    }

    /// A config with mode 0400. The rename replaced it without a word.
    func testAFileThatIsNotWritableIsRefused() throws {
        let url = installer.configURL(for: claude)
        func mode() throws -> Int? { try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int }
        try write(foreignClaude, for: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        XCTAssertThrowsError(try installer.install(claude)) { XCTAssertEqual($0 as? HookInstallError, .notWritable) }
        XCTAssertEqual(try text(of: claude), foreignClaude)
        XCTAssertEqual(try mode(), 0o400)
        XCTAssertEqual(backups(of: claude), [])
        XCTAssertNil(installer.record(for: claude))

        // Made read-only after "on": "off" refuses too.
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        try installer.install(claude)
        XCTAssertEqual(try mode(), 0o640, "The mode stays")
        let installed = try text(of: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o440], ofItemAtPath: url.path)
        XCTAssertThrowsError(try installer.uninstall(claude)) { XCTAssertEqual($0 as? HookInstallError, .notWritable) }
        XCTAssertEqual(try text(of: claude), installed)
        XCTAssertNotNil(installer.record(for: claude), "The record is kept for the next try")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        try installer.uninstall(claude)
        XCTAssertEqual(try text(of: claude), foreignClaude)
        XCTAssertEqual(try mode(), 0o640)

        // A file that "on" made, and the plugin file.
        for entry in [codex, opencode, pi] {
            let made = installer.configURL(for: entry)
            try installer.install(entry)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: made.path)
            XCTAssertThrowsError(try installer.uninstall(entry)) { XCTAssertEqual($0 as? HookInstallError, .notWritable) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: made.path))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: made.path)
            try installer.uninstall(entry)
            XCTAssertFalse(FileManager.default.fileExists(atPath: made.path))
        }
        XCTAssertTrue(HookInstallError.notWritable.message(file: "~/.claude/settings.json").contains("read-only"))
    }

    // MARK: opencode

    func testPluginFile() throws {
        let url = installer.configURL(for: opencode)
        XCTAssertEqual(installer.status(of: opencode), .notInstalled)
        try installer.install(opencode)
        XCTAssertEqual(installer.status(of: opencode), .installed(version: HookCatalog.pluginVersion))
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("\"/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook\""))
        XCTAssertEqual(HookInstaller(home: home, appPath: "/elsewhere/agent caffeine.app").status(of: opencode), .outdated)
        try installer.uninstall(opencode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("export const Mine = async () => ({})".utf8).write(to: url)
        XCTAssertEqual(installer.status(of: opencode), .unreadable)
        XCTAssertThrowsError(try installer.install(opencode)) { XCTAssertEqual($0 as? HookInstallError, .notOurFile) }
        XCTAssertThrowsError(try installer.uninstall(opencode)) { XCTAssertEqual($0 as? HookInstallError, .notOurFile) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// The plugin of version 1, as it is on a Mac that turned it on before.
    private func pluginVersion1(appPath: String) -> String {
        """
        // agent-caffeine-hook v=1
        // Written by agent caffeine. Turn it off in agent caffeine > Preferences > Agents.
        // It tells agent caffeine when opencode works, waits for you or is done.
        const hook = "\(appPath)/Contents/MacOS/CaffeinagentHook";

        const named = (event) => {
          const properties = event?.properties ?? {};
          switch (event?.type) {
            case "session.status": {
              const status = typeof properties.status === "string" ? properties.status : properties.status?.type;
              if (status === "busy" || status === "retry") return "session.busy";
              return status === "idle" ? "session.idle" : null;
            }
            case "session.idle":
            case "session.deleted":
            case "permission.asked":
            case "permission.replied":
              return event.type;
            default:
              return null;
          }
        };

        export const AgentCaffeine = async ({ $ }) => ({
          event: async ({ event }) => {
            try {
              const name = named(event);
              if (!name) return;
              const properties = event?.properties ?? {};
              const session = properties.sessionID ?? properties.info?.id ?? "";
              const input = new Response(JSON.stringify({ session_id: String(session) }));
              await $`${hook} opencode ${name} v=1 < ${input}`.quiet().nothrow();
            } catch {}
          },
        });

        """
    }

    func testPluginSourceHasTheQueueAndTheStamp() {
        let source = HookCatalog.pluginSource(appPath: appPath)
        XCTAssertEqual(HookCatalog.pluginVersion, 3)
        XCTAssertTrue(source.hasPrefix("// agent-caffeine-hook v=3\n"))
        XCTAssertFalse(source.contains("v=1"))
        XCTAssertFalse(source.contains("v=2"))
        for piece in [
            "let queue = Promise.resolve();",
            "queue = queue.then(() => run(name, body));",
            "JSON.stringify({ session_id: session, seq, ts, inst })",
            "const ts = Date.now();",
            "if (key === last && Math.abs(ts - lastAt) < 1000) return;",
            "opencode ${name} v=3 < ${input}`.quiet().nothrow().then(end, end);",
            Self.pluginTimer,
        ] {
            XCTAssertTrue(source.contains(piece), piece)
        }
        // `event` gives the hook command to the queue and does not wait for it.
        XCTAssertFalse(source.contains("await queue"))
        // The entries of the other agents keep their version, so they do not read as outdated.
        XCTAssertEqual(HookCatalog.version, 1)
        XCTAssertTrue(HookCatalog.command(agent: "claude", event: "Stop").contains(" v=1 "))
    }

    func testThePluginOfVersion1IsOutdatedAndReplaced() throws {
        let url = installer.configURL(for: opencode)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(pluginVersion1(appPath: appPath).utf8).write(to: url)
        XCTAssertEqual(installer.status(of: opencode), .outdated)
        try installer.install(opencode)
        XCTAssertEqual(installer.status(of: opencode), .installed(version: 3))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), HookCatalog.pluginSource(appPath: appPath))
        let folder = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(folder, [HookCatalog.pluginFileName], "opencode loads every file of the folder, so no backup is left there")

        // "Off" takes the file away, the new one and one that is still of version 1.
        try installer.uninstall(opencode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try Data(pluginVersion1(appPath: appPath).utf8).write(to: url)
        try installer.uninstall(opencode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path), [])
    }

    private static let pluginTimer = "const timer = setTimeout(done, 5000);"

    /// A JavaScript runtime of this Mac. Skips the test when there is none.
    private func javaScriptRuntime() throws -> String {
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.bun/bin"]
        let runtimes = folders.flatMap { folder in ["node", "bun"].map { "\(folder)/\($0)" } }
        guard let runtime = runtimes.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("No node and no bun on this Mac.")
        }
        return runtime
    }

    /// Runs `runner.mjs` of the folder and gives the JSON it prints.
    private func runJavaScript(in folder: URL) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try javaScriptRuntime())
        process.arguments = [folder.appendingPathComponent("runner.mjs").path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// One hook command never ends. The events after it still reach the
    /// hook command, in their order, when its time is over.
    func testAHookCommandThatHangsDoesNotHoldBackTheLaterEventsOfThePlugin() throws {
        _ = try javaScriptRuntime()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = HookCatalog.pluginSource(appPath: appPath)
        XCTAssertEqual(source.components(separatedBy: Self.pluginTimer).count, 2)
        // The same file with a wait of 80 ms, so the test does not take 5 seconds.
        let quick = source.replacingOccurrences(of: Self.pluginTimer, with: "const timer = setTimeout(done, 80);")
        try Data(quick.utf8).write(to: folder.appendingPathComponent("plugin.mjs"))
        let runner = """
        import { AgentCaffeine } from "./plugin.mjs";
        const log = [];
        let calls = 0;
        const $ = (strings, ...values) => {
          calls += 1;
          const call = calls;
          const work = (async () => {
            const body = JSON.parse(await values[2].text());
            if (call === 2) await new Promise(() => {});
            log.push({ name: values[1], seq: body.seq, inst: body.inst, at: Date.now() });
          })();
          const command = { quiet: () => command, nothrow: () => command, then: (a, b) => work.then(a, b) };
          return command;
        };
        const plugin = await AgentCaffeine({ $ });
        const other = await AgentCaffeine({ $ });
        const fire = (type, properties) => plugin.event({ event: { id: "e", type, properties } });
        const started = Date.now();
        await fire("session.status", { sessionID: "s", status: { type: "busy" } });
        await fire("permission.asked", { sessionID: "s" });
        await fire("permission.replied", { sessionID: "s" });
        await fire("session.idle", { sessionID: "s" });
        await new Promise((done) => setTimeout(done, 40));
        const early = log.length;
        await new Promise((done) => setTimeout(done, 400));
        await other.event({ event: { id: "e", type: "session.idle", properties: { sessionID: "s" } } });
        await new Promise((done) => setTimeout(done, 40));
        console.log(JSON.stringify({ log, calls, early, started }));
        """
        try Data(runner.utf8).write(to: folder.appendingPathComponent("runner.mjs"))
        let result = try runJavaScript(in: folder)
        let log = try XCTUnwrap(result["log"] as? [[String: Any]])
        XCTAssertEqual(result["early"] as? Int, 1, "The queue waits for the command that hangs")
        XCTAssertEqual(result["calls"] as? Int, 5)
        XCTAssertEqual(log.map { $0["name"] as? String }, ["session.busy", "permission.replied", "session.idle", "session.idle"])
        XCTAssertEqual(log.map { $0["seq"] as? Int }, [1, 3, 4, 1])
        // Each plugin instance counts on its own and says which one it is.
        let instances = log.compactMap { $0["inst"] as? String }
        XCTAssertEqual(instances.count, 4)
        XCTAssertEqual(Set(instances.prefix(3)).count, 1)
        XCTAssertNotEqual(instances[0], instances[3])
        XCTAssertGreaterThanOrEqual(instances[0].count, 8)
        let started = try XCTUnwrap(result["started"] as? Double)
        let idle = try XCTUnwrap(log[2]["at"] as? Double)
        XCTAssertGreaterThanOrEqual(idle - started, 70, "Not before the time of the command that hangs is over")
    }

    /// Runs the plugin as it is written, with a `$` that records. Skipped
    /// on a Mac with no JavaScript runtime.
    func testThePluginHandsItsEventsOverInOrder() throws {
        _ = try javaScriptRuntime()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(HookCatalog.pluginSource(appPath: appPath).utf8).write(to: folder.appendingPathComponent("plugin.mjs"))
        // The first hook command is the slowest, so with no queue it would end last.
        let runner = """
        import { AgentCaffeine } from "./plugin.mjs";
        const log = [];
        let running = 0, overlap = false, calls = 0;
        const $ = (strings, ...values) => {
          calls += 1;
          const call = calls;
          const work = (async () => {
            running += 1;
            if (running > 1) overlap = true;
            const body = JSON.parse(await values[2].text());
            await new Promise((done) => setTimeout(done, call === 1 ? 60 : 2));
            running -= 1;
            if (call === 2) throw new Error("a hook command that fails");
            log.push({ hook: values[0], name: values[1], session: body.session_id, seq: body.seq, ts: body.ts });
          })();
          const command = { quiet: () => command, nothrow: () => command, then: (a, b) => work.then(a, b) };
          return command;
        };
        const plugin = await AgentCaffeine({ $ });
        const fire = (type, properties) => plugin.event({ event: { id: "e", type, properties } });
        const answers = [
          fire("session.status", { sessionID: "s", status: { type: "busy" } }),
          fire("session.status", { sessionID: "s", status: { type: "busy" } }),
          fire("permission.asked", { sessionID: "s" }),
          fire("permission.replied", { sessionID: "s" }),
          fire("message.updated", { info: { id: "m" } }),
          fire("session.status", { sessionID: "s", status: { type: "busy" } }),
          fire("session.status", { sessionID: "s", status: { type: "idle" } }),
          fire("session.idle", { sessionID: "s" }),
          fire("session.status", { sessionID: "other", status: "busy" }),
          fire(undefined, undefined),
        ];
        await Promise.all(answers);
        const answered = { delivered: log.length };
        await new Promise((done) => setTimeout(done, 400));
        console.log(JSON.stringify({ log, overlap, calls, answered }));
        """
        try Data(runner.utf8).write(to: folder.appendingPathComponent("runner.mjs"))
        let result = try runJavaScript(in: folder)
        let log = try XCTUnwrap(result["log"] as? [[String: Any]])

        XCTAssertEqual(result["overlap"] as? Bool, false, "One hook command at a time")
        XCTAssertEqual(result["calls"] as? Int, 6)
        // The second busy and the second idle are the same event again. The
        // hook command of the permission failed, and the queue went on.
        XCTAssertEqual(log.map { $0["name"] as? String }, ["session.busy", "permission.replied", "session.busy", "session.idle", "session.busy"])
        XCTAssertEqual(log.map { $0["session"] as? String }, ["s", "s", "s", "s", "other"])
        XCTAssertEqual(log.map { $0["seq"] as? Int }, [1, 3, 4, 5, 6])
        let times = log.compactMap { $0["ts"] as? Double }
        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(log.first?["hook"] as? String, "\(appPath)/Contents/MacOS/CaffeinagentHook")
        // opencode got its answer before one hook command had ended.
        let answered = try XCTUnwrap(result["answered"] as? [String: Any])
        XCTAssertEqual(answered["delivered"] as? Int, 0)
    }

    // MARK: Pi

    func testPiExtensionFile() throws {
        let url = installer.configURL(for: pi)
        XCTAssertEqual(url.path, home.appendingPathComponent(".pi/agent/extensions/agent-caffeine.js").path)
        // An extension of the user is in the folder, and stays as it is.
        let mine = url.deletingLastPathComponent().appendingPathComponent("mine.ts")
        let mineBytes = Data("export default function (pi) {\r\n\tpi.on(\"agent_start\", () => {});\r\n}".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try mineBytes.write(to: mine)

        XCTAssertEqual(installer.status(of: pi), .notInstalled)
        try installer.install(pi)
        XCTAssertEqual(installer.status(of: pi), .installed(version: HookCatalog.piExtensionVersion))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), HookCatalog.piExtensionSource(appPath: appPath))
        XCTAssertNotEqual(HookCatalog.piExtensionSource(appPath: appPath), HookCatalog.pluginSource(appPath: appPath))
        XCTAssertEqual(HookInstaller(home: home, appPath: "/elsewhere/agent caffeine.app").status(of: pi), .outdated)
        // On again changes nothing.
        try installer.install(pi)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).sorted(), ["agent-caffeine.js", "mine.ts"])

        try installer.uninstall(pi)
        XCTAssertEqual(installer.status(of: pi), .notInstalled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path), ["mine.ts"], "Pi loads every file of the folder, so no backup is left there")
        XCTAssertEqual(try Data(contentsOf: mine), mineBytes)
        XCTAssertNil(installer.record(for: pi))

        // A file of an older build is ours: it is replaced, and "off" takes it away.
        let older = "// agent-caffeine-hook v=0\nexport default function (pi) {}\n"
        try Data(older.utf8).write(to: url)
        XCTAssertEqual(installer.status(of: pi), .outdated)
        try installer.install(pi)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), HookCatalog.piExtensionSource(appPath: appPath))
        try Data(older.utf8).write(to: url)
        try installer.uninstall(pi)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // A file of that name that is not ours is never touched.
        let foreign = Data("export default function (pi) {}".utf8)
        try foreign.write(to: url)
        XCTAssertEqual(installer.status(of: pi), .unreadable)
        XCTAssertThrowsError(try installer.install(pi)) { XCTAssertEqual($0 as? HookInstallError, .notOurFile) }
        XCTAssertThrowsError(try installer.uninstall(pi)) { XCTAssertEqual($0 as? HookInstallError, .notOurFile) }
        XCTAssertEqual(try Data(contentsOf: url), foreign)
    }

    func testPiIsNotOfferedOnAMacWithNoPi() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let other = HookInstaller(home: empty, appPath: appPath)
        XCTAssertEqual(other.status(of: pi), .configMissing)
        XCTAssertThrowsError(try other.install(pi)) { XCTAssertEqual($0 as? HookInstallError, .configMissing) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.appendingPathComponent(".pi").path))
        XCTAssertEqual(HookRowModel.rows(statuses: ["pi": .configMissing]), [])
        XCTAssertEqual(HookRowModel.rows(statuses: ["pi": .notInstalled]).map(\.entry.displayName), ["Pi"])
    }

    func testPiExtensionSourceHasTheQueueAndTheStamp() {
        let source = HookCatalog.piExtensionSource(appPath: appPath)
        XCTAssertEqual(HookCatalog.piExtensionVersion, 2)
        XCTAssertTrue(source.hasPrefix("// agent-caffeine-hook v=2\n"))
        XCTAssertFalse(source.contains("v=1"))
        XCTAssertFalse(source.contains(".v1"))
        for piece in [
            Self.piSpawnImport,
            "const hook = \"/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook\";",
            "export default function (pi) {",
            "globalThis[Symbol.for(\"agent-caffeine.pi.v2\")] ??= {",
            "queue: Promise.resolve(),",
            "seq: 0,",
            "shared.queue = shared.queue.then(() => run(name, body));",
            "JSON.stringify({ session_id: session || \"pid-\" + process.pid, seq: shared.seq, ts, inst: shared.inst })",
            "const ts = Date.now();",
            "if (key === last && Math.abs(ts - lastAt) < 1000) return;",
            "spawn(hook, [\"pi\", name, \"v=2\"], { stdio: [\"pipe\", \"ignore\", \"ignore\"], detached: true });",
            "child?.kill(\"SIGKILL\");",
            Self.piTimer,
            "child.unref();",
        ] {
            XCTAssertTrue(source.contains(piece), piece)
        }
        // A handler gives the hook command to the queue and returns: Pi waits for each handler.
        XCTAssertFalse(source.contains("await"))
        XCTAssertFalse(source.contains("async"))
        // Every event of the table is taken, and no other. A handler of
        // `tool_call` that fails blocks the tool.
        for event in pi.events { XCTAssertTrue(source.contains("\"\(event)\""), event) }
        let quoted = source.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let named = Set(quoted.filter { $0.contains("_") && $0.allSatisfy { $0 == "_" || $0.isLowercase } })
        XCTAssertEqual(named, Set(pi.events))
        XCTAssertFalse(source.contains("\u{2014}"))
        // The entries of the other agents and the opencode plugin keep their version.
        XCTAssertEqual(HookCatalog.version, 1)
        XCTAssertEqual(HookCatalog.pluginVersion, 3)
        XCTAssertEqual(HookCatalog.pluginSource(for: opencode, appPath: appPath), HookCatalog.pluginSource(appPath: appPath))
        XCTAssertEqual(HookCatalog.pluginVersion(for: opencode), 3)
        XCTAssertEqual(pi.benefit, "Lets agent caffeine see at once when Pi starts and stops working")
    }

    private static let piSpawnImport = "import { spawn } from \"node:child_process\";"
    private static let piTimer = "}, 5000);"

    /// One hook command never exits. It is killed when its time is over,
    /// and the events after it reach the hook command in their order.
    func testAHookCommandThatHangsIsKilledAndThePiExtensionGoesOn() throws {
        _ = try javaScriptRuntime()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pi-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = HookCatalog.piExtensionSource(appPath: appPath)
        XCTAssertEqual(source.components(separatedBy: Self.piSpawnImport).count, 2)
        XCTAssertEqual(source.components(separatedBy: Self.piTimer).count, 2)
        // The same file with a wait of 80 ms, so the test does not take 5 seconds.
        let wired = source.replacingOccurrences(of: Self.piSpawnImport, with: "import { spawn } from \"./spawn.mjs\";")
            .replacingOccurrences(of: Self.piTimer, with: "}, 80);")
        try Data(wired.utf8).write(to: folder.appendingPathComponent("extension.mjs"))
        // The second child never exits. The kill of the fourth one throws.
        let spawn = """
        export const state = { log: [], kills: [], calls: 0 };
        export const spawn = (command, args) => {
          state.calls += 1;
          const call = state.calls;
          const handlers = {};
          const child = {
            on: (name, handler) => {
              handlers[name] = handler;
              return child;
            },
            unref: () => {},
            kill: (signal) => {
              state.kills.push({ call, signal });
              if (call === 4) throw new Error("ESRCH");
            },
            stdin: {
              on: () => {},
              end: (body) => {
                if (call === 2 || call === 4) return;
                const input = JSON.parse(body);
                setTimeout(() => {
                  state.log.push({ name: args[1], seq: input.seq, inst: input.inst, keys: Object.keys(input), at: Date.now() });
                  handlers.close(0);
                }, 2);
              },
            },
          };
          return child;
        };
        """
        try Data(spawn.utf8).write(to: folder.appendingPathComponent("spawn.mjs"))
        let runner = """
        import extension from "./extension.mjs";
        import { state } from "./spawn.mjs";
        const handlers = {};
        extension({ on: (name, handler) => { (handlers[name] ??= []).push(handler); } });
        const context = { sessionManager: { getSessionId: () => "s" } };
        const fire = (name) => { for (const handler of handlers[name]) handler({ type: name }, context); };
        const started = Date.now();
        fire("session_start");
        fire("agent_start");
        fire("tool_execution_start");
        fire("tool_execution_end");
        fire("agent_settled");
        await new Promise((done) => setTimeout(done, 40));
        const early = { delivered: state.log.length, kills: state.kills.length };
        await new Promise((done) => setTimeout(done, 400));
        console.log(JSON.stringify({ log: state.log, kills: state.kills, calls: state.calls, early, started }));
        """
        try Data(runner.utf8).write(to: folder.appendingPathComponent("runner.mjs"))
        let result = try runJavaScript(in: folder)
        let log = try XCTUnwrap(result["log"] as? [[String: Any]])
        let early = try XCTUnwrap(result["early"] as? [String: Any])
        XCTAssertEqual(early["delivered"] as? Int, 1, "The queue waits for the command that hangs")
        XCTAssertEqual(early["kills"] as? Int, 0, "No kill before the time is over")
        XCTAssertEqual(result["calls"] as? Int, 5)
        XCTAssertEqual(log.map { $0["name"] as? String }, ["session_start", "tool_execution_start", "agent_settled"])
        XCTAssertEqual(log.map { $0["seq"] as? Int }, [1, 3, 5])
        let kills = try XCTUnwrap(result["kills"] as? [[String: Any]])
        XCTAssertEqual(kills.map { $0["call"] as? Int }, [2, 4], "Only the commands that hang, and a kill that throws stops nothing")
        XCTAssertEqual(kills.map { $0["signal"] as? String }, ["SIGKILL", "SIGKILL"])
        // The stamp says which Pi process counts.
        let instances = Set(log.compactMap { $0["inst"] as? String })
        XCTAssertEqual(instances.count, 1)
        XCTAssertGreaterThanOrEqual(instances.first?.count ?? 0, 8)
        XCTAssertEqual(log.first?["keys"] as? [String], ["session_id", "seq", "ts", "inst"])
        let started = try XCTUnwrap(result["started"] as? Double)
        let settled = try XCTUnwrap(log.last?["at"] as? Double)
        XCTAssertGreaterThanOrEqual(settled - started, 150, "Two commands ran out of their time before it")
    }

    /// Runs the extension as it is written, with a `pi` that records the
    /// handlers and a `spawn` that records. All events fire in one tick,
    /// as Pi does. Skipped on a Mac with no JavaScript runtime.
    func testThePiExtensionHandsItsEventsOverInOrder() throws {
        _ = try javaScriptRuntime()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pi-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = HookCatalog.piExtensionSource(appPath: appPath)
        XCTAssertEqual(source.components(separatedBy: Self.piSpawnImport).count, 2)
        let wired = source.replacingOccurrences(of: Self.piSpawnImport, with: "import { spawn } from \"./spawn.mjs\";")
        try Data(wired.utf8).write(to: folder.appendingPathComponent("extension.mjs"))
        // The first hook command is the slowest, so with no queue it would
        // end last. The second one cannot start, and the third `spawn` throws.
        let spawn = """
        export const state = { log: [], running: 0, overlap: false, calls: 0 };
        export const spawn = (command, args, options) => {
          state.calls += 1;
          const call = state.calls;
          if (call === 3) throw new Error("a spawn that throws");
          const handlers = {};
          state.running += 1;
          if (state.running > 1) state.overlap = true;
          const child = {
            unrefed: false,
            on: (name, handler) => {
              handlers[name] = handler;
              return child;
            },
            unref: () => {
              child.unrefed = true;
            },
            stdin: {
              on: () => {},
              end: (body) => {
                setTimeout(() => {
                  state.running -= 1;
                  if (call === 2) return handlers.error(new Error("ENOENT"));
                  const input = JSON.parse(body);
                  state.log.push({ command, args, options, unrefed: child.unrefed, keys: Object.keys(input), session: input.session_id, seq: input.seq, ts: input.ts });
                  handlers.close(0);
                }, call === 1 ? 60 : 2);
              },
            },
          };
          return child;
        };
        """
        try Data(spawn.utf8).write(to: folder.appendingPathComponent("spawn.mjs"))
        let runner = """
        import extension from "./extension.mjs";
        import { state } from "./spawn.mjs";
        const load = () => {
          const handlers = {};
          const answer = extension({ on: (name, handler) => { (handlers[name] ??= []).push(handler); } });
          return { handlers, answer };
        };
        const first = load();
        const answers = [first.answer];
        const context = (id) => ({ sessionManager: { getSessionId: () => id } });
        const stale = { get sessionManager() { throw new Error("a context of a session that is gone"); } };
        const fire = (loaded, name, ctx = context("s")) => {
          for (const handler of loaded.handlers[name]) answers.push(handler({ type: name }, ctx));
        };
        fire(first, "session_start");
        fire(first, "agent_start");
        fire(first, "turn_start");
        fire(first, "tool_execution_start");
        fire(first, "tool_execution_start");
        fire(first, "ui_prompt_start");
        fire(first, "tool_execution_end");
        fire(first, "ui_prompt_end");
        fire(first, "tool_execution_end");
        fire(first, "session_compact");
        fire(first, "agent_settled");
        fire(first, "ui_prompt_start");
        fire(first, "ui_prompt_end");
        fire(first, "session_before_compact");
        fire(first, "session_compact");
        fire(first, "agent_start", stale);
        // Pi loads the extension anew for `/reload` and for a new session.
        const second = load();
        answers.push(second.answer);
        fire(second, "session_start", context("t"));
        fire(first, "session_shutdown");
        let threw = false;
        try {
          extension({ on: () => { throw new Error("a pi that refuses"); } });
          extension(undefined);
        } catch {
          threw = true;
        }
        const answered = { delivered: state.log.length, plain: answers.every((answer) => answer === undefined) };
        await new Promise((done) => setTimeout(done, 400));
        console.log(JSON.stringify({ log: state.log, overlap: state.overlap, calls: state.calls, answered, threw, events: Object.keys(first.handlers) }));
        """
        try Data(runner.utf8).write(to: folder.appendingPathComponent("runner.mjs"))
        let result = try runJavaScript(in: folder)
        let log = try XCTUnwrap(result["log"] as? [[String: Any]])

        XCTAssertEqual(Set(try XCTUnwrap(result["events"] as? [String])), Set(pi.events))
        XCTAssertEqual(result["threw"] as? Bool, false, "The extension never throws into Pi")
        XCTAssertEqual(result["overlap"] as? Bool, false, "One hook command at a time")
        XCTAssertEqual(result["calls"] as? Int, 13)
        // Left out: the same event again, the work of another tool during a
        // question, the end of a compaction inside a run, and a question
        // outside a run. The hook commands that could not start are passed
        // over, and the queue went on.
        XCTAssertEqual(log.map { $0["args"] as? [String] }, [
            "session_start", "tool_execution_start", "ui_prompt_start", "ui_prompt_end", "tool_execution_end", "agent_settled",
            "session_before_compact", "session_compact", "agent_start", "session_start", "session_shutdown",
        ].map { ["pi", $0, "v=2"] })
        XCTAssertEqual(log.map { $0["seq"] as? Int }, [1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
        XCTAssertEqual(log.map { $0["session"] as? String }, ["s", "s", "s", "s", "s", "s", "s", "s", "s", "t", "s"])
        let times = log.compactMap { $0["ts"] as? Double }
        XCTAssertEqual(times.count, 11)
        XCTAssertEqual(times, times.sorted())
        for entry in log {
            XCTAssertEqual(entry["command"] as? String, "\(appPath)/Contents/MacOS/CaffeinagentHook")
            XCTAssertEqual(entry["keys"] as? [String], ["session_id", "seq", "ts", "inst"], "Nothing else leaves Pi")
            XCTAssertEqual(entry["unrefed"] as? Bool, true)
            let options = try XCTUnwrap(entry["options"] as? [String: Any])
            XCTAssertEqual(options["detached"] as? Bool, true)
            XCTAssertEqual(options["stdio"] as? [String], ["pipe", "ignore", "ignore"])
        }
        // Pi got every answer at once, before one hook command had ended.
        let answered = try XCTUnwrap(result["answered"] as? [String: Any])
        XCTAssertEqual(answered["delivered"] as? Int, 0)
        XCTAssertEqual(answered["plain"] as? Bool, true)
    }

    // MARK: What Preferences shows

    func testPreviewShowsTheLinesThatAreAdded() throws {
        let preview = HookConfigEditor.preview(for: codex, appPath: appPath)
        for event in codex.events { XCTAssertTrue(preview.contains("hooks.\(event):"), event) }
        XCTAssertTrue(preview.contains(HookCatalog.command(agent: "codex", event: "PermissionRequest", appPath: appPath).replacingOccurrences(of: "\"", with: "\\\"")))
        XCTAssertEqual(installer.displayPath(for: codex), "~/.codex/hooks.json")
        XCTAssertEqual(HookConfigEditor.preview(for: opencode, appPath: appPath), HookCatalog.pluginSource(appPath: appPath))
        XCTAssertEqual(HookConfigEditor.preview(for: pi, appPath: appPath), HookCatalog.piExtensionSource(appPath: appPath))
        XCTAssertEqual(installer.displayPath(for: pi), "~/.pi/agent/extensions/agent-caffeine.js")
    }

    func testErrorMessagesArePlain() {
        for error in [HookInstallError.configMissing, .unreadable, .unexpectedShape, .changedWhileEditing, .notOurFile, .notWritable, .writeFailed] {
            let message = error.message(file: "~/.codex/hooks.json")
            XCTAssertTrue(message.contains("~/.codex/hooks.json"))
            XCTAssertFalse(message.contains("\u{2014}"))
        }
    }
}
