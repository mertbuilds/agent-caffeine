import Foundation

/// One agent that loads `SKILL.md` skills from a folder of the user.
struct SkillCatalogEntry: Equatable, Identifiable {
    let id: String
    let displayName: String
    /// The folder that shows the agent is set up, relative to the home folder.
    let homeFolder: String
    /// The skills folders of the user that the agent reads, relative to
    /// the home folder. The first one is where Agent Caffeine writes when
    /// none of them holds the skill yet.
    let places: [String]
    /// What the folders were checked against, and when.
    let confirmedBy: String
}

/// Where the skill of the command line tool goes. The skill itself is
/// `skills/agent-caffeine/SKILL.md` of the repo, bundled into the app.
/// The research is `docs/research/13-agent-skills.md`.
enum SkillCatalog {
    /// Raised when the text of the skill changes, so a file of an older
    /// build reads as outdated. `SkillTextTests` holds the digest of the
    /// text of each version. 2: the tool is found under both names of the
    /// app. 3: no trial is a stop, and the file names its own license.
    static let version = 3
    static let skillName = "agent-caffeine"
    static let fileName = "SKILL.md"
    /// Every file we write holds this line after the frontmatter, and the
    /// text in the repo does not. So a copy of the skill that the user got
    /// from elsewhere is never taken for ours.
    static let marker = "agent-caffeine-skill"
    /// The skill in the app bundle, below `Contents`.
    static let pathInApp = "/Contents/Resources/skills/\(skillName)/\(fileName)"
    /// Read by Codex, opencode, Cursor, Gemini CLI, Pi, Droid, Grok Build,
    /// Amp, goose and OpenClaw. For Codex and Pi it is the only folder of
    /// the user that their docs name.
    static let sharedPlace = ".agents/skills"

    static let entries: [SkillCatalogEntry] = [
        SkillCatalogEntry(
            id: "claude", displayName: "Claude Code", homeFolder: ".claude",
            places: [".claude/skills"],
            confirmedBy: "code.claude.com/docs/en/skills, read 2026-10-09: personal skills are ~/.claude/skills/<skill-name>/SKILL.md"
        ),
        SkillCatalogEntry(
            id: "codex", displayName: "Codex", homeFolder: ".codex",
            places: [sharedPlace],
            confirmedBy: "learn.chatgpt.com/docs/build-skills, read 2026-10-09: the user folder is $HOME/.agents/skills. ~/.codex/skills is no longer named there and is left out."
        ),
        SkillCatalogEntry(
            id: "opencode", displayName: "opencode", homeFolder: ".config/opencode",
            places: [".config/opencode/skills", ".claude/skills", sharedPlace],
            confirmedBy: "opencode.ai/docs/skills, read 2026-10-09: ~/.config/opencode/skills/*/SKILL.md, ~/.claude/skills/*/SKILL.md, ~/.agents/skills/*/SKILL.md"
        ),
        SkillCatalogEntry(
            id: "cursor", displayName: "Cursor", homeFolder: ".cursor",
            places: [".cursor/skills", sharedPlace, ".claude/skills"],
            confirmedBy: "cursor.com/docs/context/skills, read 2026-10-09: ~/.agents/skills/ and ~/.cursor/skills/, and ~/.claude/skills/ as a compatibility path"
        ),
        SkillCatalogEntry(
            id: "gemini", displayName: "Gemini CLI", homeFolder: ".gemini",
            places: [".gemini/skills", sharedPlace],
            confirmedBy: "geminicli.com/docs/cli/skills, read 2026-10-09: user skills are in ~/.gemini/skills/ or the ~/.agents/skills/ alias"
        ),
        SkillCatalogEntry(
            id: "pi", displayName: "Pi", homeFolder: ".pi/agent",
            places: [sharedPlace],
            confirmedBy: "docs/skills.md of Pi 1.0.4 on the test Mac, read 2026-10-09: \"Pi also supports the Agent Skills locations ~/.agents/skills/\". The docs name no path for a folder of Pi's own, so none is used."
        ),
        SkillCatalogEntry(
            id: "droid", displayName: "Droid", homeFolder: ".factory",
            places: [".factory/skills", sharedPlace],
            confirmedBy: "docs.factory.com/cli/configuration/skills, read 2026-10-09: ~/.factory/skills/<skill-name>/SKILL.md, and ~/.agents/skills/**/SKILL.md as a compatibility path"
        ),
        SkillCatalogEntry(
            id: "grok", displayName: "Grok Build", homeFolder: ".grok",
            places: [".grok/skills", sharedPlace, ".claude/skills", ".cursor/skills"],
            confirmedBy: "~/.grok/docs/user-guide/08-skills.md of Grok Build on the test Mac, read 2026-10-09: ~/.grok/skills/, .agents/skills/ at each tier, and ~/.claude/skills/ and ~/.cursor/skills/ unless the user turned that off in ~/.grok/config.toml"
        ),
        SkillCatalogEntry(
            id: "amp", displayName: "Amp", homeFolder: ".config/amp",
            places: [".config/amp/skills", sharedPlace, ".claude/skills"],
            confirmedBy: "ampcode.com/docs/customize/skills, read 2026-10-09: ~/.config/agents/skills/, ~/.agents/skills/, ~/.config/amp/skills/ and ~/.claude/skills/"
        ),
        SkillCatalogEntry(
            id: "goose", displayName: "goose", homeFolder: ".config/goose",
            places: [sharedPlace, ".claude/skills"],
            confirmedBy: "goose-docs.ai/docs/guides/context-engineering/using-skills, read 2026-10-09: ~/.agents/skills/ for global skills, and ~/.claude/skills/ for older setups"
        ),
        SkillCatalogEntry(
            id: "openclaw", displayName: "OpenClaw", homeFolder: ".openclaw",
            places: [sharedPlace],
            confirmedBy: "docs.openclaw.ai/tools/skills, read 2026-10-09: personal agent skills are ~/.agents/skills, with the state folder at its default place. ~/.openclaw/skills is managed by OpenClaw and is left alone."
        ),
    ]

    /// Agents with skills that are left out, and why.
    static let notConfirmed: [(agent: String, reason: String)] = [
        ("Hermes Agent", "Its docs name ~/.hermes/skills as the folder the agent manages itself, and do not say where a user puts a skill by hand. It reads ~/.agents/skills only when the user adds it to skills.external_dirs."),
    ]

    static func entry(id: String) -> SkillCatalogEntry? {
        entries.first { $0.id == id }
    }

    /// Every folder a skill of ours can be in, each once.
    static var places: [String] {
        var seen: Set<String> = []
        return entries.flatMap(\.places).filter { seen.insert($0).inserted }
    }

    // MARK: The text

    static func markerLine(version: Int = version) -> String {
        "<!-- \(marker) v=\(version) -->"
    }

    /// The text of the file we write: the skill with our line after the
    /// frontmatter. Nil for a text without frontmatter.
    static func installedText(of skill: String, version: Int = version) -> String? {
        guard let end = frontmatterEnd(of: skill) else { return nil }
        return String(skill[..<end]) + "\n" + markerLine(version: version) + "\n" + String(skill[end...])
    }

    /// Nil for a file that is not ours.
    static func version(ofInstalled text: String) -> Int? {
        guard let range = text.range(of: "<!-- \(marker) v=(\\d+) -->", options: .regularExpression) else { return nil }
        let digits = text[range].dropFirst("<!-- \(marker) v=".count).prefix { $0.isNumber }
        return Int(digits)
    }

    /// The keys of the frontmatter, for a text that starts with `---` and
    /// has one `key: value` per line. Nil without frontmatter.
    static func frontmatter(of skill: String) -> [String: String]? {
        guard let end = frontmatterEnd(of: skill) else { return nil }
        var fields: [String: String] = [:]
        for line in skill[..<end].split(separator: "\n").dropFirst().dropLast() {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    /// The index after the line that closes the frontmatter.
    private static func frontmatterEnd(of skill: String) -> String.Index? {
        guard skill.hasPrefix("---\n"), let close = skill.range(of: "\n---\n", range: skill.index(skill.startIndex, offsetBy: 3)..<skill.endIndex) else { return nil }
        return close.upperBound
    }

    /// The skill of the copy of the app that runs. Nil when it is not in
    /// the bundle.
    static func bundledSkill(appPath: String) -> String? {
        try? String(contentsOfFile: appPath + pathInApp, encoding: .utf8)
    }
}
