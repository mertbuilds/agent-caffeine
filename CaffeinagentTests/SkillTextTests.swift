import CryptoKit
import XCTest

/// The skill of the repo, the catalog of the agents that read skills,
/// the check of the PATH and what Settings says about all of it.
final class SkillTextTests: XCTestCase {
    private let skill = SkillInstallerTests.repoSkill

    // MARK: The skill

    func testTheFrontmatterIsWhatEveryAgentTakes() throws {
        let fields = try XCTUnwrap(SkillCatalog.frontmatter(of: skill))
        XCTAssertEqual(Set(fields.keys), ["name", "description"])
        XCTAssertEqual(fields["name"], SkillCatalog.skillName)
        XCTAssertEqual(fields["name"], "agent-caffeine", "The name of the folder, as opencode and Cursor ask")
        XCTAssertNotNil(fields["name"]?.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression))
        let description = try XCTUnwrap(fields["description"])
        XCTAssertFalse(description.isEmpty)
        XCTAssertLessThan(description.count, 1024)
        XCTAssertFalse(description.contains("\n"))
    }

    func testTheSkillFollowsTheHouseStyle() {
        XCTAssertFalse(skill.contains("\u{2014}"))
        XCTAssertTrue(skill.contains("Agent Caffeine"))
        // The lowercase name is the path of the app, and nothing else.
        XCTAssertEqual(skill.components(separatedBy: "agent caffeine").count - 1, skill.components(separatedBy: "agent caffeine.app").count - 1)
        XCTAssertTrue(skill.contains("\"\(HookCatalog.stableAppPath)\(CommandLineSetup.pathInApp)\""), "The full path, in quotes for its space")
    }

    /// A change of the text needs a new `SkillCatalog.version`, or the
    /// copies that are installed never get it. Add the digest of the new
    /// text here and keep the old lines.
    func testTheTextAndItsVersionChangeTogether() {
        let digests = [1: "ff96577727c2073f4a708bbcc944b4a060c8e742dc892ebb456332f133467246"]
        let digest = SHA256.hash(data: Data(skill.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digests[SkillCatalog.version], digest)
    }

    func testOurLineMarksTheFileWeWriteAndNotTheSkillOfTheRepo() throws {
        XCTAssertNil(SkillCatalog.version(ofInstalled: skill), "A copy from elsewhere is not ours")
        let installed = try XCTUnwrap(SkillCatalog.installedText(of: skill))
        XCTAssertEqual(SkillCatalog.version(ofInstalled: installed), SkillCatalog.version)
        XCTAssertEqual(SkillCatalog.frontmatter(of: installed), SkillCatalog.frontmatter(of: skill))
        XCTAssertTrue(installed.contains("\n---\n\n<!-- agent-caffeine-skill v=\(SkillCatalog.version) -->\n\n# Agent Caffeine\n"))
        XCTAssertEqual(installed.replacingOccurrences(of: "\n\(SkillCatalog.markerLine())\n", with: ""), skill)
        XCTAssertEqual(SkillCatalog.version(ofInstalled: "<!-- agent-caffeine-skill v=12 -->"), 12)
        XCTAssertNil(SkillCatalog.installedText(of: "No frontmatter."))
    }

    /// Each word after `agent-caffeine` in the text is a command the tool
    /// has, each line of a code block is a call the tool takes, and each
    /// option is one of its own.
    func testTheSkillNamesOnlyWhatTheToolHas() throws {
        let verbs = try NSRegularExpression(pattern: "agent-caffeine ([a-z]+)")
        let all = NSRange(skill.startIndex..., in: skill)
        var named: Set<String> = []
        for match in verbs.matches(in: skill, range: all) {
            named.insert(String(skill[try XCTUnwrap(Range(match.range(at: 1), in: skill))]))
        }
        XCTAssertEqual(named, ["hold", "release", "status"])
        for verb in named {
            if case .failure(let error) = HoldArguments.parse([verb]) { XCTFail("\(verb): \(error.message)") }
        }
        var calls = 0
        for line in skill.components(separatedBy: "\n") where line.hasPrefix("agent-caffeine ") {
            let arguments = Self.words(String(line.dropFirst("agent-caffeine ".count)))
            if case .failure(let error) = HoldArguments.parse(arguments) { XCTFail("\(line): \(error.message)") }
            calls += 1
        }
        XCTAssertEqual(calls, 6)
        let options = try NSRegularExpression(pattern: "(?<![a-z-])--[a-z]+")
        let used = Set(options.matches(in: skill, range: all).compactMap { Range($0.range, in: skill).map { String(skill[$0]) } })
        XCTAssertEqual(used, ["--for", "--reason", "--json", "--all"])
        for tool in ["hold_awake", "release", "status"] {
            XCTAssertTrue(skill.contains("`\(tool)`"), tool)
        }
        XCTAssertTrue(skill.contains("from 1 to \(Int(ManualHold.timedCap / 60))"))
        XCTAssertTrue(skill.contains("cut to \(ManualHold.reasonLimit) characters"))
    }

    /// As a shell splits a line: by spaces, with double quotes around a text.
    private static func words(_ line: String) -> [String] {
        var words: [String] = [], word = "", quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == " ", !quoted {
                if !word.isEmpty { words.append(word) }
                word = ""
            } else {
                word.append(character)
            }
        }
        return word.isEmpty ? words : words + [word]
    }

    // MARK: The tool

    func testTheToolPrintsTheSkillOfItsApp() throws {
        XCTAssertEqual(try HoldArguments.parse(["skill"]).get(), .skill)
        XCTAssertTrue(HoldArguments.usage.contains("agent-caffeine skill "))
        if case .success = HoldArguments.parse(["skill", "--install"]) { XCTFail("The tool installs nothing") }
        XCTAssertEqual(
            URL(fileURLWithPath: "/A.app" + CommandLineSetup.pathInApp).deletingLastPathComponent().appendingPathComponent(HoldCommands.skillFromTool).standardizedFileURL.path,
            "/A.app" + SkillCatalog.pathInApp, "The tool and the app look in one place"
        )
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("skill-app-\(UUID().uuidString)/agent caffeine.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let tool = URL(fileURLWithPath: app.path + CommandLineSetup.pathInApp)
        let file = URL(fileURLWithPath: app.path + SkillCatalog.pathInApp)
        try FileManager.default.createDirectory(at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: tool)
        XCTAssertEqual(HoldCommands.skill(executable: tool).code, HoldOutcome.failed)
        XCTAssertEqual(HoldCommands.skill(executable: nil).code, HoldOutcome.failed)
        try Data(skill.utf8).write(to: file)
        XCTAssertEqual(SkillCatalog.bundledSkill(appPath: app.path), skill)
        XCTAssertEqual(HoldCommands.skill(executable: tool), HoldOutcome(out: [String(skill.dropLast())]), "The line break at the end is the one of the output")
        // As the link in ~/.local/bin calls it.
        let link = app.deletingLastPathComponent().appendingPathComponent("agent-caffeine")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        XCTAssertEqual(HoldCommands.skill(executable: link).out, [String(skill.dropLast())])
    }

    // MARK: The catalog

    func testEveryEntryNamesItsFoldersAndItsSource() {
        XCTAssertEqual(Set(SkillCatalog.entries.map(\.id)).count, SkillCatalog.entries.count)
        for entry in SkillCatalog.entries {
            XCTAssertFalse(entry.places.isEmpty, entry.id)
            XCTAssertTrue(entry.confirmedBy.contains("read 2026-"), entry.id)
            for path in entry.places + [entry.homeFolder] {
                XCTAssertTrue(path.hasPrefix("."), "\(entry.id): \(path) is a folder of an agent below the home folder")
                XCTAssertFalse(path.contains(".."), path)
                XCTAssertFalse(path.hasSuffix("/"), path)
            }
            for place in entry.places { XCTAssertTrue(place.hasSuffix("/skills"), place) }
            // The first folder is the agent's own, or the shared one.
            XCTAssertTrue(entry.places[0].hasPrefix(entry.homeFolder + "/") || entry.places[0] == SkillCatalog.sharedPlace, entry.id)
        }
        XCTAssertEqual(SkillCatalog.entry(id: "claude")?.places, [".claude/skills"])
        XCTAssertEqual(SkillCatalog.entry(id: "codex")?.places, [".agents/skills"])
        XCTAssertEqual(SkillCatalog.entry(id: "opencode")?.places.first, ".config/opencode/skills")
        XCTAssertEqual(SkillCatalog.places.count, Set(SkillCatalog.places).count)
        XCTAssertFalse(SkillCatalog.notConfirmed.isEmpty)
    }

    // MARK: The PATH

    func testWhetherLocalBinIsOnThePath() {
        let home = "/Users/me"
        let cases: [(name: String, shell: String, path: String?, files: [String], expected: Bool?)] = [
            ("on the PATH of the login shell", "/bin/zsh", "/usr/bin:/Users/me/.local/bin:/bin", [], true),
            ("not on it, and no file names it", "/bin/zsh", "/usr/bin:/bin", ["export EDITOR=vi"], false),
            ("set for an interactive shell only", "/bin/zsh", "/usr/bin:/bin", ["export PATH=\"$HOME/.local/bin:$PATH\""], true),
            ("a file names it, and the shell gave no answer", "/bin/bash", nil, [". \"$HOME/.local/bin/env\""], true),
            ("the shell gave no answer", "/bin/zsh", nil, [], nil),
            ("the shell gave an empty PATH", "/bin/zsh", "", [], nil),
            ("a shell we do not know", "/opt/homebrew/bin/fish", "/usr/bin:/Users/me/.local/bin", [], nil),
            ("with a slash at the end", "/bin/bash", "/Users/me/.local/bin/:/bin", [], true),
            ("of another user", "/bin/zsh", "/Users/you/.local/bin:/bin", [], false),
        ]
        for c in cases {
            XCTAssertEqual(ShellPath.hasLocalBin(shell: c.shell, home: home, loginPath: c.path, startupFiles: c.files), c.expected, c.name)
        }
        XCTAssertEqual(ShellPath.startupFile(shell: "/bin/zsh"), "~/.zshrc")
        XCTAssertEqual(ShellPath.startupFile(shell: "/bin/bash"), "~/.bash_profile")
        XCTAssertNil(ShellPath.startupFile(shell: "/opt/homebrew/bin/fish"))
        XCTAssertEqual(ShellPath.exportLine, "export PATH=\"$HOME/.local/bin:$PATH\"")
    }

    func testThePathIsReadBetweenOurMarks() {
        XCTAssertEqual(ShellPath.path(inOutput: "Welcome back\n__agent_caffeine_path__/usr/bin:/bin__end__"), "/usr/bin:/bin")
        XCTAssertEqual(ShellPath.path(inOutput: "__agent_caffeine_path____end__"), "")
        XCTAssertNil(ShellPath.path(inOutput: "/usr/bin:/bin"))
        XCTAssertNil(ShellPath.path(inOutput: "__agent_caffeine_path__/usr/bin"))
    }

    func testTheStartupFilesAreReadBelowTheGivenHome() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("shell-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        XCTAssertEqual(ShellPath.startupFiles(shell: "/bin/zsh", home: home), [])
        try Data("export PATH=\"$HOME/.local/bin:$PATH\"\n".utf8).write(to: home.appendingPathComponent(".zshrc"))
        XCTAssertEqual(ShellPath.startupFiles(shell: "/bin/zsh", home: home), ["export PATH=\"$HOME/.local/bin:$PATH\"\n"])
        XCTAssertEqual(ShellPath.startupFiles(shell: "/bin/bash", home: home), [])
    }

    // MARK: Settings

    private func model(
        _ statuses: [(String, SkillAgentStatus)], link: SkillLinkState = .none, linkAllowed: Bool = true, planned: [String] = []
    ) -> AgentSetupModel {
        AgentSetupModel(snapshot: SkillSnapshot(
            agents: statuses.compactMap { id, status in SkillCatalog.entry(id: id).map { SkillSnapshot.Agent(entry: $0, status: status) } },
            link: link, linkAllowed: linkAllowed, planned: planned
        ))
    }

    func testWhatTheButtonSaysItDoes() {
        let fresh = model([("claude", .notInstalled), ("codex", .notInstalled), ("opencode", .notInstalled)], planned: [".claude/skills", ".agents/skills"])
        XCTAssertEqual(fresh.summary, "Adds a skill to Claude Code, Codex and opencode, and links the command agent-caffeine.")
        XCTAssertEqual(fresh.changes, ["~/.claude/skills/agent-caffeine/SKILL.md", "~/.agents/skills/agent-caffeine/SKILL.md", "~/.local/bin/agent-caffeine"])
        XCTAssertFalse(fresh.isSetUp)
        XCTAssertTrue(fresh.isOffered)
        XCTAssertEqual(model([("claude", .notInstalled)]).summary, "Adds a skill to Claude Code, and links the command agent-caffeine.")
        XCTAssertEqual(model([("claude", .notInstalled), ("codex", .notInstalled)], link: .foreign).summary, "Adds a skill to Claude Code and Codex.")
        let none = model([])
        XCTAssertEqual(none.summary, "Links the command agent-caffeine. No agent that reads skills was found on this Mac.")
        XCTAssertFalse(none.isOffered, "The setup window has no step for a Mac without an agent that reads skills")
        XCTAssertNil(model([("claude", .installed(place: ".claude/skills"))], link: .ours(target: "/x")).summary)
        XCTAssertEqual(PanelText.list([]), "")
        XCTAssertEqual(PanelText.list(["Pi"]), "Pi")
    }

    func testTheRowsAfterTheSetup() {
        let done = model(
            [("claude", .installed(place: ".claude/skills")), ("codex", .outdated(place: ".agents/skills")), ("gemini", .notInstalled), ("droid", .foreign(place: ".factory/skills"))],
            link: .ours(target: "/x")
        )
        XCTAssertTrue(done.isSetUp)
        XCTAssertTrue(done.isOffered, "An agent that came later")
        XCTAssertEqual(done.pending.map(\.id), ["codex", "gemini"])
        XCTAssertEqual(done.snapshot.agents.map { AgentSetupModel.detail($0.status) }, [
            "The skill is in ~/.claude/skills/agent-caffeine",
            "The skill in ~/.agents/skills/agent-caffeine is from another version of Agent Caffeine.",
            "No skill yet",
            "~/.factory/skills/agent-caffeine was not made by Agent Caffeine, so it is left as it is.",
        ])
        XCTAssertEqual(done.snapshot.agents.map { AgentSetupModel.action($0.status) }, [nil, "Update", "Install", nil])
        XCTAssertEqual(done.linkDetail, "Linked in ~/.local/bin")
        XCTAssertFalse(done.canLink)
        XCTAssertTrue(model([], link: .ours(target: "/x")).isSetUp, "The link alone is something to remove")
        XCTAssertFalse(model([("droid", .foreign(place: ".factory/skills"))], link: .foreign).isSetUp)
        XCTAssertEqual(model([], link: .foreign).linkDetail, "~/.local/bin/agent-caffeine was not made by Agent Caffeine, so it is left as it is.")
        XCTAssertTrue(model([], link: .dangling).canLink)
    }

    func testALinkToACopyThatIsGoneIsNotLinked() {
        let dead = model([("claude", .installed(place: ".claude/skills"))], link: .dead)
        XCTAssertFalse(dead.isLinked)
        XCTAssertTrue(dead.canLink, "Link repairs it")
        XCTAssertEqual(dead.linkDetail, "Not linked")
        XCTAssertNil(dead.linkNote)
        XCTAssertEqual(model([], link: .dead).changes, ["~/.local/bin/agent-caffeine"])
    }

    func testOutsideTheApplicationsFolderTheLinkIsNotOffered() {
        let line = "Move Agent Caffeine to the Applications folder to link the command."
        let fresh = model([("claude", .notInstalled)], linkAllowed: false, planned: [".claude/skills"])
        XCTAssertFalse(fresh.canLink)
        XCTAssertEqual(fresh.summary, "Adds a skill to Claude Code.")
        XCTAssertEqual(fresh.changes, ["~/.claude/skills/agent-caffeine/SKILL.md"])
        XCTAssertEqual(fresh.linkNote, line)
        XCTAssertTrue(fresh.isOffered, "The skill does not need the Applications folder")
        let none = model([], linkAllowed: false)
        XCTAssertNil(none.summary, "Nothing to do, so the button is off")
        XCTAssertEqual(none.linkNote, line)
        let dead = model([("claude", .installed(place: ".claude/skills"))], link: .dead, linkAllowed: false)
        XCTAssertFalse(dead.canLink)
        XCTAssertEqual(dead.linkDetail, line)
        let linked = model([], link: .ours(target: "/x"), linkAllowed: false)
        XCTAssertEqual(linked.linkDetail, "Linked in ~/.local/bin", "A link to the copy in the Applications folder is shown as it is")
        XCTAssertNil(linked.linkNote)
    }

    func testTheLineAboutThePathIsShownOnlyWhenItIsKnown() {
        var linked = model([], link: .ours(target: "/x"))
        XCTAssertNil(linked.pathHint, "Not known")
        linked.localBinOnPath = false
        XCTAssertNil(linked.pathHint, "A shell with no file we know")
        linked.startupFile = "~/.zshrc"
        XCTAssertEqual(linked.pathHint, "~/.local/bin does not seem to be on your PATH. If your shell does not find agent-caffeine, add this line to ~/.zshrc.")
        linked.localBinOnPath = true
        XCTAssertNil(linked.pathHint)
        var unlinked = model([])
        unlinked.localBinOnPath = false
        unlinked.startupFile = "~/.zshrc"
        XCTAssertNil(unlinked.pathHint, "No link, no line")
    }

    func testErrorsThatBelongToNoRowAreStillShown() {
        var setup = model([("claude", .notInstalled)])
        setup.errors = ["claude": "a", SkillInstaller.linkKey: "b", ".agents/skills": "c"]
        XCTAssertEqual(setup.otherErrors, ["c"])
    }

    func testTheTextsFollowTheHouseStyle() {
        var texts = [
            PanelText.agentSetupButton, PanelText.agentSetupExplained, PanelText.agentSetupOptional, PanelText.agentSetupRemoveExplained,
            PanelText.agentSetupByHand, PanelText.agentSetupUnavailable, PanelText.commandLinkTitle, PanelText.skillNotInstalled,
            PanelText.commandLinked, PanelText.commandNotLinked, PanelText.commandLinkNeedsApplications, PanelText.localBinNotOnPath(file: "~/.zshrc"),
            PanelText.skillInstalled(in: "x"), PanelText.skillOutdated(in: "x"), PanelText.skillForeign("x"),
            PanelText.agentSetupSummary(agents: ["Pi"], links: true) ?? "",
        ]
        for error in [SkillInstallError.notOurs, .linkedOutside, .notAFolder, .writeFailed, .noTool, .linkNotOurs, .notInApplications] {
            texts += [error.message(place: ".claude/skills"), error.linkMessage]
        }
        texts += SkillCatalog.entries.map(\.displayName)
        for text in texts {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("agent caffeine"), text)
            XCTAssertFalse(text.contains("\u{2014}"), text)
        }
        XCTAssertEqual(PanelText.agentSetupButton, "Set up for agents")
    }
}
