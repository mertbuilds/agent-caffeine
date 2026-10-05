import XCTest

final class HookInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: HookInstaller!
    private let claude = HookCatalog.entry(id: "claude")!
    private let codex = HookCatalog.entry(id: "codex")!
    private let droid = HookCatalog.entry(id: "droid")!
    private let opencode = HookCatalog.entry(id: "opencode")!
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
        for folder in [".claude", ".codex", ".factory", ".config/opencode"] {
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
        XCTAssertEqual(try text(of: claude), "{}\n")
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

    func testTwoChangesInOneSecondKeepBothBackups() throws {
        installer.now = { Date(timeIntervalSince1970: 1_791_000_000) }
        try write(foreignCodex, for: codex)
        try installer.install(codex)
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
            try installer.uninstall(codex)
        }
        XCTAssertEqual(backups(of: codex).count, HookInstaller.backupsKept)
        XCTAssertEqual(try text(of: codex), foreignCodex)
    }

    // MARK: opencode

    func testPluginFile() throws {
        let url = installer.configURL(for: opencode)
        XCTAssertEqual(installer.status(of: opencode), .notInstalled)
        try installer.install(opencode)
        XCTAssertEqual(installer.status(of: opencode), .installed(version: HookCatalog.version))
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

    // MARK: What Preferences shows

    func testPreviewShowsTheLinesThatAreAdded() throws {
        let preview = HookConfigEditor.preview(for: codex, appPath: appPath)
        for event in codex.events { XCTAssertTrue(preview.contains("hooks.\(event):"), event) }
        XCTAssertTrue(preview.contains(HookCatalog.command(agent: "codex", event: "PermissionRequest", appPath: appPath).replacingOccurrences(of: "\"", with: "\\\"")))
        XCTAssertEqual(installer.displayPath(for: codex), "~/.codex/hooks.json")
        XCTAssertEqual(HookConfigEditor.preview(for: opencode, appPath: appPath), HookCatalog.pluginSource(appPath: appPath))
    }

    func testErrorMessagesArePlain() {
        for error in [HookInstallError.configMissing, .unreadable, .unexpectedShape, .changedWhileEditing, .notOurFile, .writeFailed] {
            let message = error.message(file: "~/.codex/hooks.json")
            XCTAssertTrue(message.contains("~/.codex/hooks.json"))
            XCTAssertFalse(message.contains("\u{2014}"))
        }
    }
}
