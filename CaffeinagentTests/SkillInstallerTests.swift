import CryptoKit
import XCTest

/// "Set up for agents", with a temp folder that stands in for the home
/// folder. Nothing here reads or writes the real one.
final class SkillInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: SkillInstaller!
    private let manager = FileManager.default

    static let repoSkill: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills/agent-caffeine/SKILL.md")
        return (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }()

    private var expected: String { SkillCatalog.installedText(of: Self.repoSkill) ?? "" }
    private let claudeFile = ".claude/skills/agent-caffeine/SKILL.md"
    private let sharedFile = ".agents/skills/agent-caffeine/SKILL.md"
    private let link = ".local/bin/agent-caffeine"

    override func setUpWithError() throws {
        home = manager.temporaryDirectory.appendingPathComponent("skill-home-\(UUID().uuidString)")
        let tool = home.appendingPathComponent("Apps/agent caffeine.app/Contents/MacOS/agent-caffeine")
        try manager.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        installer = SkillInstaller(home: home, skill: Self.repoSkill, toolPath: tool.path, stableToolPath: tool.path)
    }

    override func tearDownWithError() throws {
        try? manager.removeItem(at: home)
    }

    private func url(_ path: String) -> URL { home.appendingPathComponent(path) }

    /// The tool in a second copy of the app, below the stand-in for the
    /// apps. With `linked`, `~/.local/bin/agent-caffeine` points at it.
    private func otherCopy(_ folder: String = "Downloads", linked: Bool = false) throws -> String {
        let tool = "Apps/\(folder)/agent caffeine.app/Contents/MacOS/agent-caffeine"
        try write("#!/bin/sh\n", to: tool)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url(tool).path)
        if linked {
            try make(".local/bin")
            try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: url(tool).path)
        }
        return url(tool).path
    }

    private func make(_ folders: String...) throws {
        for folder in folders { try manager.createDirectory(at: url(folder), withIntermediateDirectories: true) }
    }

    private func write(_ text: String, to path: String) throws {
        try manager.createDirectory(at: url(path).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url(path))
    }

    private func text(_ path: String) -> String? {
        try? String(contentsOf: url(path), encoding: .utf8)
    }

    /// True also for a link whose destination is gone.
    private func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(url(path).path, &info) == 0
    }

    private func destination(_ path: String) -> String? {
        try? manager.destinationOfSymbolicLink(atPath: url(path).path)
    }

    private func status(_ id: String) throws -> SkillAgentStatus {
        installer.status(of: try XCTUnwrap(SkillCatalog.entry(id: id)))
    }

    /// Everything below the home folder but the stand-in for the app.
    private func tree() -> [String] {
        (manager.enumerator(atPath: home.path)?.compactMap { $0 as? String } ?? [])
            .filter { !$0.hasPrefix("Apps") }.sorted()
    }

    // MARK: Install

    func testSetUpWritesForTheAgentsThatAreFoundAndNoOther() throws {
        try make(".claude", ".codex", ".config/opencode")
        XCTAssertEqual(installer.snapshot().planned, [".claude/skills", ".agents/skills"])
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(tree(), [
            ".agents", ".agents/skills", ".agents/skills/agent-caffeine", sharedFile,
            ".claude", ".claude/skills", ".claude/skills/agent-caffeine", claudeFile,
            ".codex", ".config", ".config/opencode",
            ".local", ".local/bin", link,
            "Library", "Library/Application Support", "Library/Application Support/com.caffeinagent.app",
            "Library/Application Support/com.caffeinagent.app/skill-installs",
            "Library/Application Support/com.caffeinagent.app/skill-installs/record.json",
        ])
        XCTAssertEqual(text(claudeFile), expected)
        XCTAssertEqual(text(sharedFile), expected)
        XCTAssertEqual(destination(link), installer.toolPath)
        let snapshot = installer.snapshot()
        XCTAssertEqual(snapshot.agents.map(\.id), ["claude", "codex", "opencode"], "Only the agents whose folder is there")
        XCTAssertEqual(snapshot.agents.map(\.status), [
            .installed(place: ".claude/skills"), .installed(place: ".agents/skills"), .installed(place: ".claude/skills"),
        ], "opencode reads the folder of Claude Code, and gets no second copy")
        XCTAssertEqual(snapshot.link, .ours(target: installer.toolPath))
        XCTAssertEqual(snapshot.planned, [])
    }

    func testAnAgentWithNoSharedFolderInUseGetsItsOwn() throws {
        try make(".config/opencode", ".gemini")
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(text(".config/opencode/skills/agent-caffeine/SKILL.md"), expected)
        XCTAssertEqual(text(".gemini/skills/agent-caffeine/SKILL.md"), expected)
        XCTAssertFalse(exists(".agents"), "No agent here needs the shared folder")
        XCTAssertFalse(exists(".claude"))
    }

    func testWithNoAgentOnlyTheLinkIsMade() {
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(installer.snapshot().agents, [])
        XCTAssertEqual(destination(link), installer.toolPath)
        XCTAssertEqual(tree().filter { $0.contains("skills") }, [])
    }

    func testAnAgentThatCameLaterGetsInstall() throws {
        try make(".claude")
        installer.setUp()
        try make(".gemini")
        XCTAssertEqual(try status("gemini"), .notInstalled)
        try installer.install(for: try XCTUnwrap(SkillCatalog.entry(id: "gemini")))
        XCTAssertEqual(try status("gemini"), .installed(place: ".gemini/skills"))
        XCTAssertEqual(text(".gemini/skills/agent-caffeine/SKILL.md"), expected)
    }

    func testSetUpTwiceChangesNothing() throws {
        try make(".claude", ".codex")
        installer.setUp()
        let before = try manager.attributesOfItem(atPath: url(claudeFile).path)[.modificationDate] as? Date
        let record = installer.record()
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(try manager.attributesOfItem(atPath: url(claudeFile).path)[.modificationDate] as? Date, before)
        XCTAssertEqual(installer.record(), record)
    }

    // MARK: Refusals

    func testAFolderThatIsNotOursIsRefused() throws {
        try make(".claude")
        try write("---\nname: agent-caffeine\ndescription: Mine.\n---\n\nMine.\n", to: claudeFile)
        XCTAssertEqual(installer.setUp()["claude"], nil, "It is left as it is, and that is no failure")
        XCTAssertEqual(text(claudeFile), "---\nname: agent-caffeine\ndescription: Mine.\n---\n\nMine.\n")
        XCTAssertEqual(try status("claude"), .foreign(place: ".claude/skills"))
        XCTAssertThrowsError(try installer.install(place: ".claude/skills")) { XCTAssertEqual($0 as? SkillInstallError, .notOurs) }
        XCTAssertThrowsError(try installer.install(for: try XCTUnwrap(SkillCatalog.entry(id: "claude")))) {
            XCTAssertEqual($0 as? SkillInstallError, .notOurs)
        }
        XCTAssertEqual(
            SkillInstallError.notOurs.message(place: ".claude/skills"),
            "~/.claude/skills/agent-caffeine was not made by Agent Caffeine, so it did not change it."
        )
        installer.removeAll()
        XCTAssertEqual(text(claudeFile), "---\nname: agent-caffeine\ndescription: Mine.\n---\n\nMine.\n")
    }

    func testAnEmptyFolderAndALinkOfThatNameAreRefused() throws {
        try make(".claude/skills/agent-caffeine", ".codex", ".agents/skills", "elsewhere/agent-caffeine")
        try manager.createSymbolicLink(at: url(".agents/skills/agent-caffeine"), withDestinationURL: url("elsewhere/agent-caffeine"))
        installer.setUp()
        XCTAssertEqual(try status("claude"), .foreign(place: ".claude/skills"))
        XCTAssertEqual(try status("codex"), .foreign(place: ".agents/skills"))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: url(".claude/skills/agent-caffeine").path), [])
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: url("elsewhere/agent-caffeine").path), [], "The link was not followed")
        XCTAssertThrowsError(try installer.install(place: ".agents/skills")) { XCTAssertEqual($0 as? SkillInstallError, .notOurs) }
    }

    func testASkillsFolderLinkedOutOfTheAgentsFolderIsRefused() throws {
        try make(".claude", "elsewhere/skills")
        try manager.createSymbolicLink(at: url(".claude/skills"), withDestinationURL: url("elsewhere/skills"))
        let errors = installer.setUp()
        XCTAssertEqual(errors["claude"], "~/.claude/skills is a link to a folder outside ~/.claude, so Agent Caffeine did not write there.")
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: url("elsewhere/skills").path), [])
        XCTAssertEqual(try status("claude"), .notInstalled)
        XCTAssertThrowsError(try installer.install(place: ".claude/skills")) { XCTAssertEqual($0 as? SkillInstallError, .linkedOutside) }
    }

    func testASkillsFolderLinkedInsideTheAgentsFolderIsUsed() throws {
        try make(".claude/my-skills")
        try manager.createSymbolicLink(at: url(".claude/skills"), withDestinationURL: url(".claude/my-skills"))
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(text(".claude/my-skills/agent-caffeine/SKILL.md"), expected)
        installer.removeAll()
        XCTAssertFalse(exists(".claude/my-skills/agent-caffeine"))
        XCTAssertEqual(destination(".claude/skills"), url(".claude/my-skills").path, "The user's link stays")
    }

    /// A common setup: one real skills folder, and the folders of the
    /// agents are links to it.
    func testAFolderLinkedToTheSharedFolderReadsTheSkillThere() throws {
        try make(".claude", ".codex", ".agents/skills")
        try manager.createSymbolicLink(at: url(".claude/skills"), withDestinationURL: url(".agents/skills"))
        XCTAssertEqual(installer.setUp(), [:], "Claude Code reads the skill through its link, so the refusal is no failure")
        XCTAssertEqual(text(sharedFile), expected)
        XCTAssertEqual(try status("claude"), .installed(place: ".claude/skills"))
        XCTAssertEqual(installer.removeAll(), [:])
        XCTAssertFalse(exists(".agents/skills/agent-caffeine"))
        XCTAssertTrue(exists(".agents/skills"), "It was there before")
        XCTAssertEqual(destination(".claude/skills"), url(".agents/skills").path)
    }

    func testASkillsPathThatIsAFileIsRefused() throws {
        try make(".claude")
        try write("x", to: ".claude/skills")
        XCTAssertEqual(installer.setUp()["claude"], "~/.claude/skills is not a folder, so Agent Caffeine did not write there.")
        XCTAssertEqual(text(".claude/skills"), "x")
    }

    // MARK: The link

    func testARealFileAtTheLinkPathIsRefused() throws {
        try write("#!/bin/sh\necho mine\n", to: link)
        let errors = installer.setUp()
        XCTAssertEqual(errors[SkillInstaller.linkKey], "~/.local/bin/agent-caffeine was not made by Agent Caffeine, so it did not change it.")
        XCTAssertEqual(text(link), "#!/bin/sh\necho mine\n")
        XCTAssertNil(destination(link))
        XCTAssertEqual(installer.linkState(), .foreign)
        XCTAssertThrowsError(try installer.link()) { XCTAssertEqual($0 as? SkillInstallError, .linkNotOurs) }
        installer.removeAll()
        XCTAssertEqual(text(link), "#!/bin/sh\necho mine\n")
    }

    func testALinkToSomethingElseIsRefused() throws {
        try write("other", to: "tools/other")
        try make(".local/bin")
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: url("tools/other").path)
        XCTAssertNotNil(installer.setUp()[SkillInstaller.linkKey])
        XCTAssertEqual(destination(link), url("tools/other").path)
        installer.removeAll()
        XCTAssertEqual(destination(link), url("tools/other").path)
    }

    func testOurOwnLinkIsReplaced() throws {
        let old = try otherCopy(linked: true)
        XCTAssertEqual(installer.linkState(), .ours(target: old), "Ours by where it points")
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(destination(link), installer.toolPath, "The copy in the Applications folder moves it")
        XCTAssertEqual(installer.record().link, SkillInstallRecord.Link(created: [], target: installer.toolPath))
        installer.removeAll()
        XCTAssertFalse(exists(link))
        XCTAssertTrue(exists(".local/bin"), "It was there before")
    }

    func testACopyOutsideTheApplicationsFolderLeavesOurLinkToAnotherCopy() throws {
        let applications = installer.toolPath
        try make(".local/bin")
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: applications)
        installer.toolPath = try otherCopy()
        XCTAssertFalse(installer.isInApplications)
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(destination(link), applications)
        XCTAssertThrowsError(try installer.link()) { XCTAssertEqual($0 as? SkillInstallError, .notInApplications) }
        XCTAssertEqual(destination(link), applications)
        XCTAssertEqual(installer.record().link, nil)
        XCTAssertEqual(SkillInstallError.notInApplications.linkMessage, "Move Agent Caffeine to the Applications folder to link the command.")
        let snapshot = installer.snapshot()
        XCTAssertEqual(snapshot.link, .ours(target: applications))
        XCTAssertFalse(snapshot.linkAllowed)
    }

    func testACopyOutsideTheApplicationsFolderIsNotLinkedBySetUp() throws {
        try make(".claude")
        installer.toolPath = try otherCopy()
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(text(claudeFile), expected, "The skill does not need the Applications folder")
        XCTAssertFalse(exists(".local"))
        XCTAssertEqual(installer.record().link, nil)
        XCTAssertFalse(installer.snapshot().linkAllowed)
    }

    func testOurLinkToACopyThatIsGoneIsDeadAndAnyCopyRepairsIt() throws {
        try make(".local/bin")
        let old = "/Somewhere/agent caffeine.app/Contents/MacOS/agent-caffeine"
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: old)
        XCTAssertEqual(installer.linkState(), .dead, "Not linked, though it points into a copy of the app")
        installer.toolPath = try otherCopy()
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(destination(link), old, "Set up for agents makes no link from outside the Applications folder")
        try installer.link()
        XCTAssertEqual(destination(link), installer.toolPath)
        XCTAssertEqual(installer.linkState(), .ours(target: installer.toolPath))
    }

    func testRemoveTakesOurDeadLink() throws {
        try make(".local/bin")
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: "/Somewhere/agent caffeine.app/Contents/MacOS/agent-caffeine")
        XCTAssertEqual(installer.removeAll(), [:])
        XCTAssertFalse(exists(link))
        XCTAssertTrue(exists(".local/bin"))
    }

    func testADanglingLinkIsReplaced() throws {
        try make(".local/bin")
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: "/nowhere/gone")
        XCTAssertEqual(installer.linkState(), .dangling)
        XCTAssertEqual(installer.setUp(), [:])
        XCTAssertEqual(destination(link), installer.toolPath)
    }

    func testNoLinkWithoutTheTool() throws {
        installer.toolPath = url("Apps/none").path
        installer.stableToolPath = installer.toolPath
        XCTAssertEqual(
            installer.setUp()[SkillInstaller.linkKey],
            "The command line tool is not in this copy of Agent Caffeine, so no link was made."
        )
        XCTAssertFalse(exists(".local"))
    }

    // MARK: Update

    /// A file as a build with an older skill wrote it, with its record.
    private func plantOlder(_ body: String = "Older words.\n", recorded: Bool = true) throws -> String {
        let old = try XCTUnwrap(SkillCatalog.installedText(of: "---\nname: agent-caffeine\ndescription: Older.\n---\n\n\(body)", version: SkillCatalog.version - 1))
        try write(old, to: claudeFile)
        if recorded {
            let digest = SHA256.hash(data: Data(old.utf8)).map { String(format: "%02x", $0) }.joined()
            var record = installer.record()
            record.places[".claude/skills"] = SkillInstallRecord.Place(created: [".claude/skills/agent-caffeine"], digest: digest, version: SkillCatalog.version - 1)
            try manager.createDirectory(at: installer.recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: installer.recordURL)
        }
        return old
    }

    func testAnOlderSkillOfOursIsUpdatedAtLaunch() throws {
        try make(".claude")
        _ = try plantOlder()
        XCTAssertEqual(try status("claude"), .outdated(place: ".claude/skills"))
        XCTAssertEqual(installer.updateOwn(), [".claude/skills"])
        XCTAssertEqual(text(claudeFile), expected)
        XCTAssertEqual(try status("claude"), .installed(place: ".claude/skills"))
        XCTAssertEqual(installer.record().places[".claude/skills"]?.version, SkillCatalog.version)
        XCTAssertEqual(installer.record().places[".claude/skills"]?.created, [".claude/skills/agent-caffeine"], "What the first time made is still known")
    }

    func testTheSameVersionIsNotWrittenAgain() throws {
        try make(".claude")
        installer.setUp()
        try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: url(claudeFile).path)
        XCTAssertEqual(installer.updateOwn(), [])
        XCTAssertEqual(try manager.attributesOfItem(atPath: url(claudeFile).path)[.modificationDate] as? Date, Date(timeIntervalSince1970: 1_000_000))
    }

    func testAnOlderSkillTheUserEditedWaitsForUpdate() throws {
        try make(".claude")
        let old = try plantOlder()
        try write(old + "My own line.\n", to: claudeFile)
        XCTAssertEqual(installer.updateOwn(), [])
        XCTAssertEqual(text(claudeFile), old + "My own line.\n")
        XCTAssertEqual(try status("claude"), .outdated(place: ".claude/skills"))
        try installer.install(for: try XCTUnwrap(SkillCatalog.entry(id: "claude")))
        XCTAssertEqual(text(claudeFile), expected, "Update is the user's word")
    }

    func testAnOlderSkillWithNoRecordWaitsForUpdate() throws {
        try make(".claude")
        let old = try plantOlder(recorded: false)
        XCTAssertEqual(installer.updateOwn(), [])
        XCTAssertEqual(text(claudeFile), old)
        XCTAssertEqual(installer.snapshot().planned, [".claude/skills"])
    }

    func testLaunchInstallsNothingNewAndMovesOnlyOurLink() throws {
        try make(".claude", ".codex")
        XCTAssertEqual(installer.updateOwn(), [])
        XCTAssertEqual(tree(), [".claude", ".codex"])
        try make(".local/bin")
        let old = "/Somewhere/agent caffeine.app/Contents/MacOS/agent-caffeine"
        try manager.createSymbolicLink(atPath: url(link).path, withDestinationPath: old)
        XCTAssertEqual(installer.updateOwn(), [link])
        XCTAssertEqual(destination(link), installer.toolPath)
        XCTAssertEqual(installer.updateOwn(), [])
    }

    // MARK: Remove

    func testRemoveTakesEverythingWeMade() throws {
        try make(".claude", ".codex")
        installer.setUp()
        XCTAssertEqual(installer.removeAll(), [:])
        XCTAssertEqual(tree(), [".claude", ".codex", "Library", "Library/Application Support", "Library/Application Support/com.caffeinagent.app"])
        XCTAssertEqual(installer.record(), SkillInstallRecord())
    }

    func testRemoveLeavesWhatIsNotOurs() throws {
        try make(".claude/skills", ".codex", ".local/bin")
        installer.setUp()
        try write("theirs", to: ".claude/skills/other-skill/SKILL.md")
        try write("notes", to: ".agents/skills/agent-caffeine/notes.txt")
        try write("tool", to: ".local/bin/other")
        XCTAssertEqual(installer.removeAll(), [:])
        XCTAssertFalse(exists(claudeFile))
        XCTAssertFalse(exists(".claude/skills/agent-caffeine"))
        XCTAssertEqual(text(".claude/skills/other-skill/SKILL.md"), "theirs")
        XCTAssertFalse(exists(sharedFile))
        XCTAssertEqual(text(".agents/skills/agent-caffeine/notes.txt"), "notes", "A file someone put into our folder stays, and the folder with it")
        XCTAssertFalse(exists(link))
        XCTAssertEqual(text(".local/bin/other"), "tool")
        XCTAssertFalse(manager.fileExists(atPath: installer.recordURL.path))
    }

    func testRemoveKeepsFoldersThatWereThereBefore() throws {
        try make(".claude/skills", ".codex", ".agents/skills", ".local/bin")
        installer.setUp()
        installer.removeAll()
        XCTAssertEqual(tree().filter { !$0.hasPrefix("Library") }, [".agents", ".agents/skills", ".claude", ".claude/skills", ".codex", ".local", ".local/bin"])
    }

    func testRemoveWithoutARecordTakesOurFilesAndOurLink() throws {
        try make(".claude", ".codex")
        installer.setUp()
        try manager.removeItem(at: installer.recordURL)
        XCTAssertEqual(installer.removeAll(), [:])
        XCTAssertFalse(exists(claudeFile))
        XCTAssertFalse(exists(".claude/skills/agent-caffeine"))
        XCTAssertFalse(exists(sharedFile))
        XCTAssertFalse(exists(link))
        XCTAssertTrue(exists(".claude/skills"), "Without the record nobody knows who made it, so it stays")
    }

    func testARecordThatNamesOtherFoldersIsNotBelieved() throws {
        try make(".claude", "empty-folder-of-the-user")
        installer.setUp()
        var record = installer.record()
        record.places[".claude/skills"]?.created.append("empty-folder-of-the-user")
        record.link?.created.append("empty-folder-of-the-user")
        try JSONEncoder().encode(record).write(to: installer.recordURL)
        installer.removeAll()
        XCTAssertTrue(exists("empty-folder-of-the-user"))
        XCTAssertFalse(exists(".claude/skills"))
    }

    // MARK: The record

    func testTheRecordRoundTrip() throws {
        try make(".claude", ".codex")
        installer.setUp()
        let record = installer.record()
        let digest = SHA256.hash(data: Data(expected.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(record, SkillInstallRecord(
            places: [
                ".claude/skills": .init(created: [".claude/skills", ".claude/skills/agent-caffeine"], digest: digest, version: SkillCatalog.version),
                ".agents/skills": .init(created: [".agents", ".agents/skills", ".agents/skills/agent-caffeine"], digest: digest, version: SkillCatalog.version),
            ],
            link: .init(created: [".local", ".local/bin"], target: installer.toolPath)
        ))
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(SkillInstallRecord.self, from: data), record)
        XCTAssertEqual(try JSONDecoder().decode(SkillInstallRecord.self, from: Data(contentsOf: installer.recordURL)), record)
        XCTAssertTrue(installer.recordURL.path.hasSuffix("/Library/Application Support/com.caffeinagent.app/skill-installs/record.json"))
        XCTAssertTrue(installer.recordURL.path.hasPrefix(home.path), "Below the home folder of the test")
    }
}
