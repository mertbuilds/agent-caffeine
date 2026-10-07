import Foundation

/// What a matched process is for its agent.
enum AgentRole: Equatable {
    /// One agent session: a CLI at a prompt or a headless run.
    case session
    /// A long-lived process that does the work of sessions which have no
    /// process of their own: a desktop app's engine, or the Codex CLI's
    /// managed daemon. Alive does not mean working.
    case engine
    /// A helper that shares the agent's name and is not a session.
    case helper
    /// A Claude Code `bg-spare`. A claimed spare is a real background
    /// session, a warm one is an idle helper, and argv is the same for both.
    /// Only `~/.claude/sessions/<pid>.json` tells them apart (a warm spare
    /// has the `spare` key and `status: idle`), so the state reader decides.
    case helperMaybeSession
}

/// Matches a process by its executable path and argv, never by its short
/// process name: Claude Code's short name is its version number.
enum ProcessMatcher: Equatable {
    /// One of `AgentCatalog.command(of:)`'s names equals this, ignoring case.
    case name(String)
    case executableSuffix(String)
    case executableContains(String)
    /// The executable path contains `path`, and the process does not run
    /// under another tool's name: argv[0] starts with `title`, or is the
    /// executable's file name, or is missing. Claude Code's binary is also
    /// its own `ugrep`, with argv[0] `ugrep`, and that is a tool call.
    case executable(contains: String, title: String)
    /// The executable is at `relativePath` inside an app bundle. `bundle` is
    /// the bundle's file name ("Antigravity.app"), nil for any bundle.
    case appBundle(bundle: String?, relativePath: String)
}

/// Matches the arguments that follow the command.
enum ArgumentPattern: Equatable {
    case any
    /// The arguments start with these.
    case leading([String])
    /// Each of these is one of the arguments, at any position.
    case contains([String])
    /// One of the arguments ends with this.
    case anySuffix(String)
    /// The first argument is one of these.
    case firstIsOne(of: Set<String>)
    /// There is one argument, and it is a file name with one of these
    /// extensions.
    case oneFile(extensions: Set<String>)
}

struct AgentMatcher: Equatable {
    let process: ProcessMatcher
    let arguments: ArgumentPattern
    /// Arguments that show another tool with the same name. A process
    /// with one of them is no agent at all, and not a helper either.
    let unless: [ArgumentPattern]

    init(_ process: ProcessMatcher, arguments: ArgumentPattern = .any, unless: [ArgumentPattern] = []) {
        self.process = process
        self.arguments = arguments
        self.unless = unless
    }
}

/// Takes a process out of the default role. Exclusions are tried in order
/// before the matchers, and the first hit gives the role.
struct AgentExclusion: Equatable {
    /// Nil means a process that the definition's matchers match.
    let process: ProcessMatcher?
    let arguments: ArgumentPattern
    let role: AgentRole

    init(process: ProcessMatcher? = nil, arguments: ArgumentPattern = .any, role: AgentRole = .helper) {
        self.process = process
        self.arguments = arguments
        self.role = role
    }
}

struct AgentDefinition: Equatable {
    enum Level: Equatable {
        /// The agent writes its own state and we read it.
        case state
        /// Known agent, judged by process activity.
        case activity
        /// A name the user added.
        case generic
    }

    enum Kind: Equatable {
        case cli
        case desktop
    }

    let id: String
    let displayName: String
    let level: Level
    let kind: Kind
    let matchers: [AgentMatcher]
    let exclusions: [AgentExclusion]
    /// True when the process shape was seen on a real Mac. False entries are
    /// carried over from the old name list or are placeholders.
    let verified: Bool

    /// The names this agent is matched by, lowercased.
    var processNames: [String] {
        matchers.compactMap { matcher in
            if case .name(let name) = matcher.process { return name.lowercased() }
            return nil
        }
    }
}

struct AgentMatch: Equatable {
    let definition: AgentDefinition
    let role: AgentRole
}

struct AgentInstance: Equatable {
    let definition: AgentDefinition
    /// Never `.helper`.
    let role: AgentRole
    let rootPID: Int32
    let rootStartTime: TimeInterval
    /// The root and its descendants, root first, without the subtrees of
    /// other instances.
    let rows: [ProcessInfoRow]

    var definitionID: String { definition.id }
    var identity: ProcessIdentity { ProcessIdentity(pid: rootPID, startTime: rootStartTime) }
}

struct AgentCatalog {
    let definitions: [AgentDefinition]

    static let standard = AgentCatalog(definitions: desktopDefinitions + cliDefinitions)

    /// Raised when a definition changes what it matches, so a lab recording
    /// says which catalog saw its processes.
    static let version = 5

    // MARK: Data

    static let cursorDesktopID = "cursor-desktop"

    /// Cursor's agent runs a command as a shell below an extension host:
    /// `Cursor Helper (Plugin)` -> `/bin/zsh -c ...` -> the command. A
    /// language server or an MCP server below the same host is no shell,
    /// and a terminal of the user is below another helper.
    static func isCursorAgentCommand(_ row: ProcessInfoRow, parent: ProcessInfoRow) -> Bool {
        parent.executablePath.contains("/Cursor.app/Contents/Frameworks/") && parent.executablePath.hasSuffix("/Cursor Helper (Plugin)")
            && cursorShells.contains(baseName(row.executablePath))
    }

    private static let cursorShells: Set<String> = ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "pwsh"]

    private static let codexDesktopEngine = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"

    static let desktopDefinitions: [AgentDefinition] = [
        // Seen 2026-10-05 inside /Applications/ChatGPT.app. The bundle name is
        // left open because the nested CodexCLI.app path is specific enough.
        AgentDefinition(
            id: "codex-desktop", displayName: "Codex", level: .state, kind: .desktop,
            matchers: [AgentMatcher(.appBundle(bundle: nil, relativePath: codexDesktopEngine), arguments: .contains(["app-server"]))],
            exclusions: [
                AgentExclusion(process: .appBundle(bundle: nil, relativePath: codexDesktopEngine), arguments: .contains(["exec-server"])),
                AgentExclusion(process: .appBundle(bundle: nil, relativePath: "Contents/Resources/codex-cli/bin/codex-code-mode-host")),
            ],
            verified: true
        ),
        // Seen 2026-10-05, Antigravity 2.19.1.
        AgentDefinition(
            id: "antigravity-desktop", displayName: "Antigravity", level: .activity, kind: .desktop,
            matchers: [AgentMatcher(.appBundle(bundle: "Antigravity.app", relativePath: "Contents/Resources/bin/language_server"))],
            exclusions: [],
            verified: true
        ),
        // Seen 2026-10-07, Cursor 3.22.12 (docs/research/08-cursor.md). The
        // engine is the main process: it owns the sleep assertion, and one
        // window can have several extension hosts. Every other binary of
        // the bundle is a helper, so none of them is taken for a CLI. The
        // helpers rewrite their titles; the executable path stays.
        //
        // The shell command `cursor` (`cursor --wait file`, as an editor
        // of git) runs the main binary as Node on `out/cli.js`, and that
        // process lives until the file is closed. It is no second Cursor.
        // Read 2026-10-07 in `Contents/Resources/app/bin/cursor`:
        // `ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$CLI" "$@"`.
        AgentDefinition(
            id: cursorDesktopID, displayName: "Cursor", level: .state, kind: .desktop,
            matchers: [AgentMatcher(.appBundle(bundle: "Cursor.app", relativePath: "Contents/MacOS/Cursor"))],
            exclusions: [
                AgentExclusion(arguments: .anySuffix("/Contents/Resources/app/out/cli.js")),
                AgentExclusion(process: .executableContains("/Cursor.app/Contents/Frameworks/")),
                AgentExclusion(process: .executableContains("/Cursor.app/Contents/Resources/")),
            ],
            verified: true
        ),
        // Placeholders. Their engine paths are unconfirmed, so they have no
        // matchers and match nothing until someone measures a running app.
        AgentDefinition(id: "claude-desktop", displayName: "Claude", level: .activity, kind: .desktop, matchers: [], exclusions: [], verified: false),
        AgentDefinition(id: "t3-code", displayName: "T3 Code", level: .activity, kind: .desktop, matchers: [], exclusions: [], verified: false),
    ]

    static let cliDefinitions: [AgentDefinition] = [
        // Seen 2026-10-05, Claude Code 2.1.286 to 2.1.289. argv[0] is `claude`
        // and the binary is `~/.local/share/claude/versions/<version>`. The
        // daemon's pty host and spares differ: their argv[0] is the whole
        // title ("claude bg-spare"), and the flag follows as argv[1]. The
        // binary also runs its built-in search tools under their own names.
        AgentDefinition(
            id: "claude", displayName: "Claude Code", level: .state, kind: .cli,
            matchers: [AgentMatcher(.name("claude")), AgentMatcher(.executable(contains: "/claude/versions/", title: "claude"))],
            exclusions: [
                AgentExclusion(arguments: .leading(["daemon", "run"])),
                AgentExclusion(arguments: .leading(["bg-pty-host"])),
                AgentExclusion(arguments: .leading(["--bg-pty-host"])),
                AgentExclusion(arguments: .leading(["bg-spare"]), role: .helperMaybeSession),
                AgentExclusion(arguments: .leading(["--bg-spare"]), role: .helperMaybeSession),
            ],
            verified: true
        ),
        // Seen 2026-10-05, Codex CLI 0.159.2. The managed daemon runs the
        // tools of every TUI session and outlives them with ppid 1, so it is
        // an engine of its own. Other `app-server` processes (IDE extensions)
        // stay excluded, as before.
        AgentDefinition(
            id: "codex", displayName: "Codex", level: .state, kind: .cli,
            matchers: [AgentMatcher(.name("codex"))],
            exclusions: [
                AgentExclusion(process: .name("codex-code-mode-host")),
                AgentExclusion(arguments: .contains(["app-server", "--managed-daemon"]), role: .engine),
                AgentExclusion(arguments: .contains(["app-server"])),
                AgentExclusion(arguments: .contains(["exec-server"])),
            ],
            verified: true
        ),
        cli("aider", "Aider"),
        cli("aider-desk", "AiderDesk"),
        cli("amp", "Amp"),
        cli("antigravity", "Antigravity"),
        cli("augment", "Augment"),
        cli("cline", "Cline"),
        cli("cn", "Continue"),
        cli("codearts-agent", "CodeArts Agent"),
        cli("codebuddy", "CodeBuddy"),
        cli("codemaker", "CodeMaker"),
        cli("codestudio", "CodeStudio"),
        cli("command-code", "Command Code"),
        // AWS Copilot is `copilot` too. Its commands that GitHub Copilot
        // does not have, by the command references of both (2026-10-07):
        // `copilot svc deploy` runs for minutes and uses the processor.
        // `app` and `init` are commands of both and stay.
        cli("copilot", "GitHub Copilot", unless: [.firstIsOne(of: ["env", "svc", "job", "task", "pipeline", "storage", "secret", "deploy"])]),
        cli("crush", "Crush"),
        cli("cursor-agent", "Cursor CLI"),
        cli("deepagents", "Deep Agents"),
        cli("devin", "Devin"),
        cli("dexto", "Dexto"),
        cli("droid", "Droid", verified: true),
        cli("firebender", "Firebender"),
        cli("forgecode", "ForgeCode"),
        cli("gemini", "Gemini CLI", names: ["gemini", "gemini-cli"]),
        // The database migration tool pressly/goose: `goose up`, `goose
        // postgres "<dsn>" status`, `goose -dir migrations create x sql`.
        // The agent has none of these commands (its command reference,
        // 2026-10-07).
        cli("goose", "Goose", unless: [
            .firstIsOne(of: [
                "up", "up-by-one", "up-to", "down", "down-to", "redo", "reset", "status", "create", "fix", "validate",
                "postgres", "mysql", "sqlite3", "mssql", "redshift", "tidb", "clickhouse", "vertica", "ydb", "turso", "starrocks",
            ]),
            .contains(["-dir"]),
        ]),
        cli("grok", "Grok", verified: true),
        cli("hermes-agent", "Hermes Agent"),
        cli("iflow-cli", "iFlow CLI"),
        cli("junie", "Junie"),
        // The text editor kilo is started as `kilo <file>`. Kilo Code
        // takes a project folder there, or a command (kilo.ai/docs/cli,
        // 2026-10-07), so one argument that is a text file is the editor.
        cli("kilo", "Kilo Code", unless: [.oneFile(extensions: textFileExtensions)]),
        cli("kiro-cli", "Kiro CLI"),
        cli("mcpjam", "MCPJam"),
        cli("mistral-vibe", "Mistral Vibe"),
        cli("neovate", "Neovate"),
        cli("opencode", "opencode", verified: true),
        cli("openclaw", "OpenClaw"),
        cli("openhands", "OpenHands"),
        cli("pi", "Pi"),
        cli("pochi", "Pochi"),
        cli("qoder", "Qoder"),
        cli("qwen-code", "Qwen Code"),
        cli("rovodev", "Rovo Dev"),
        cli("tabnine-cli", "Tabnine CLI"),
        cli("trae", "Trae", names: ["trae", "trae-cn"]),
        cli("windsurf", "Windsurf"),
        cli("zencoder", "Zencoder"),
    ]

    private static let textFileExtensions: Set<String> = [
        "c", "h", "cc", "cpp", "hpp", "txt", "md", "py", "js", "ts", "json", "yml", "yaml", "toml", "sh", "rb", "go", "rs",
        "java", "swift", "conf", "cfg", "ini", "log", "html", "css", "sql", "xml", "csv",
    ]

    /// A CLI that is matched by name only and judged by activity.
    private static func cli(
        _ id: String, _ displayName: String, names: [String]? = nil, unless: [ArgumentPattern] = [], verified: Bool = false
    ) -> AgentDefinition {
        AgentDefinition(
            id: id, displayName: displayName, level: .activity, kind: .cli,
            matchers: (names ?? [id]).map { AgentMatcher(.name($0), unless: unless) },
            exclusions: [],
            verified: verified
        )
    }

    static func userDefinition(name: String) -> AgentDefinition {
        AgentDefinition(
            id: "user:\(name)", displayName: name, level: .generic, kind: .cli,
            matchers: [AgentMatcher(.name(name))], exclusions: [], verified: false
        )
    }

    /// Every name a CLI of the catalog is matched by.
    var cliNames: Set<String> {
        Set(definitions.filter { $0.kind == .cli }.flatMap(\.processNames))
    }

    // MARK: Matching

    struct Command: Equatable {
        /// Lowercased names the process can be matched by.
        let names: [String]
        /// The arguments after the command, and after the script for a CLI
        /// that an interpreter runs.
        let arguments: [String]
        /// The executable is an interpreter and one of the names is the
        /// script it runs.
        var interpreterRunsScript = false
    }

    /// The names are the basename of argv[0] (a CLI that sets its process
    /// title lands here), the script or module when an interpreter runs it
    /// (`node /opt/homebrew/bin/gemini`, `python -m openhands`), what a
    /// package runner starts (`bun run opencode`, `npx gemini`), and the
    /// basename of the executable.
    ///
    /// A script file counts under its name only when the name has no
    /// extension, as an installed command has none: `python pi.py` is
    /// someone's own script, not Pi.
    static func command(of row: ProcessInfoRow) -> Command {
        let argv0 = baseName(row.arguments.first ?? "").lowercased()
        let executable = baseName(row.executablePath).lowercased()
        var names: [String] = []
        var arguments = Array(row.arguments.dropFirst())
        var runsScript = false
        if !argv0.isEmpty { names.append(argv0) }
        func note(_ target: (name: String, rest: [String])) {
            names.append(target.name)
            arguments = target.rest
            runsScript = isInterpreter(executable)
        }
        if let target = launched(by: argv0, arguments) {
            note(target)
        } else if let interpreter = [argv0, executable].first(where: isInterpreter), let script = script(of: interpreter, arguments) {
            note(script)
            if let target = launched(by: script.name, script.rest) { note(target) }
        }
        if !executable.isEmpty && !names.contains(executable) { names.append(executable) }
        return Command(names: names, arguments: arguments, interpreterRunsScript: runsScript)
    }

    /// The flags of each interpreter that take the next argument as their
    /// value, and the flags after which there is no script file at all.
    private static func flags(of interpreter: String) -> (valued: Set<String>, inline: Set<String>) {
        switch interpreter {
        case "node": return (["-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions", "--inspect-port", "--title"], ["-e", "--eval", "-p", "--print"])
        case "bun": return (["-r", "--preload", "--cwd", "-c", "--config", "--define", "-d"], ["-e", "--eval", "-p", "--print"])
        case "deno": return (["-c", "--config", "--import-map", "--lock", "--cert", "-L", "--log-level"], [])
        case "ruby": return (["-I", "-r", "-C", "-E"], ["-e"])
        default: return (["-W", "-X", "-Q"], ["-c"])
        }
    }

    /// The script or module an interpreter runs, and the arguments after it.
    private static func script(of interpreter: String, _ arguments: [String]) -> (name: String, rest: [String])? {
        let python = interpreter.hasPrefix("python") || interpreter.hasPrefix("pypy")
        let flags = flags(of: interpreter)
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("-"), argument != "-" else {
                return (targetName(argument), Array(arguments[(index + 1)...]))
            }
            if flags.inline.contains(argument) { return nil }
            // `python -m openhands.cli`, also as `-um`: the package is the agent.
            if python, !argument.hasPrefix("--"), argument.hasSuffix("m") {
                guard index + 1 < arguments.count else { return nil }
                let module = arguments[index + 1].split(separator: ".").first.map(String.init) ?? ""
                return (module.lowercased(), Array(arguments[(index + 2)...]))
            }
            index += flags.valued.contains(argument) ? 2 : 1
        }
        return nil
    }

    /// Package runners, with the words that come before the command they
    /// start. The longer form is tried first.
    private static let launchers: [String: [[String]]] = [
        "npx": [[]], "pnpx": [[]], "bunx": [[]], "uvx": [[]],
        "bun": [["run"], ["x"]], "deno": [["run"]],
        "pnpm": [["dlx"], ["exec"]], "yarn": [["dlx"]], "npm": [["exec"]],
        "uv": [["tool", "run"], ["run"]], "pipx": [["run"]],
    ]

    /// The flags that take the next argument as their value. A flag that
    /// is missing here turns its value into the command: `uv run
    /// --directory ~/code/aider pytest` would be aider, and `uv run
    /// --extra gemini pytest` would be Gemini. The second block is from
    /// the help of `uv run`, `uvx`, `pipx run`, `npx`, `pnpm` and `bun`:
    /// long flags only, because a short one is a switch of another runner
    /// (`bun -b`, `bun -i`).
    private static let launcherValuedFlags: Set<String> = [
        "-p", "--package", "--from", "--with", "--with-editable", "--with-requirements", "--python", "--spec",
        "-c", "--call", "--config", "--cwd", "--filter", "--import-map", "--lock", "--index-url",
        "--directory", "--project", "--env-file", "-w", "--workspace", "--prefix", "-C", "--dir",

        "--extra", "--no-extra", "--group", "--no-group", "--only-group", "--index", "--default-index", "--extra-index-url",
        "--find-links", "--constraints", "--overrides", "--build-constraints", "--config-file", "--config-setting", "--cache-dir",
        "--python-preference", "--python-platform", "--resolution", "--prerelease", "--exclude-newer", "--fork-strategy",
        "--index-strategy", "--keyring-provider", "--link-mode", "--allow-insecure-host", "--refresh-package",
        "--reinstall-package", "--upgrade-package", "--no-binary-package", "--no-build-package", "--pip-args",
        "--registry", "--userconfig", "--cache", "--loglevel", "--reporter", "--workspace-concurrency", "--loader", "--preload",
        "--define", "--port", "--log-level", "--location", "--seed",
    ]

    /// Where one runner reads a flag of the list above as a switch:
    /// `pnpm -w` is the workspace root, and `deno --env-file` takes its
    /// value after `=` only.
    private static let launcherSwitches: [String: Set<String>] = ["pnpm": ["-w"], "deno": ["--env-file"]]

    /// What a package runner starts, and the arguments after it. Nil when
    /// `name` is no runner or has none of its run words.
    private static func launched(by name: String, _ arguments: [String]) -> (name: String, rest: [String])? {
        guard let forms = launchers[name] else { return nil }
        let valued = launcherValuedFlags.subtracting(launcherSwitches[name] ?? [])
        var words: [(index: Int, value: String)] = []
        var index = 0
        while index < arguments.count, words.count < 3 {
            let argument = arguments[index]
            if argument.hasPrefix("-") {
                index += valued.contains(argument) ? 2 : 1
            } else {
                words.append((index, argument))
                index += 1
            }
        }
        for form in forms where words.count > form.count && words.prefix(form.count).map(\.value) == form {
            let target = words[form.count]
            guard isCommandTarget(target.value) else { return nil }
            return (targetName(target.value), Array(arguments[(target.index + 1)...]))
        }
        return nil
    }

    /// The net below the flag list: a runner target that is a path counts
    /// only when it is a command in a `bin` or `.bin` folder. Any other
    /// path is a folder or a file that a flag we do not know took as its
    /// value. A package (`@google/gemini-cli`, `npm:@scope/name`) is no path.
    private static func isCommandTarget(_ target: String) -> Bool {
        var name = Substring(target)
        for scheme in ["npm:", "jsr:"] where name.hasPrefix(scheme) { name = name.dropFirst(scheme.count) }
        guard !name.hasPrefix("@"), name.contains("/") else { return true }
        let folders = name.split(separator: "/", omittingEmptySubsequences: true).dropLast()
        return folders.last == "bin" || folders.last == ".bin"
    }

    /// A command name from a path or a package: `/opt/homebrew/bin/gemini`,
    /// `@google/gemini-cli@latest` and `npm:gemini` all give their last part
    /// without the version. An extension stays, so a source file matches
    /// no agent.
    private static func targetName(_ target: String) -> String {
        var name = baseName(target)
        for scheme in ["npm:", "jsr:"] where name.hasPrefix(scheme) { name.removeFirst(scheme.count) }
        if let at = name.lastIndex(of: "@"), at != name.startIndex { name = String(name[..<at]) }
        return name.lowercased()
    }

    /// The definition and role of a process, nil when it is no agent process.
    /// Desktop engines are tried first. After that, anything else inside an
    /// app bundle is no agent, so an app's helpers never count as the CLI
    /// whose name they share. An interpreter that runs a script is no such
    /// helper: the Python of Homebrew and of Xcode is itself inside a
    /// `Python.app` (`.../Python.framework/Versions/3.14/Resources/
    /// Python.app/Contents/MacOS/Python`). `userNames` is the user's editable name list;
    /// a name there that no definition covers matches at the generic level.
    func match(_ row: ProcessInfoRow, userNames: [String]) -> AgentMatch? {
        let command = Self.command(of: row)
        func firstMatch(_ kind: AgentDefinition.Kind) -> AgentMatch? {
            for definition in definitions where definition.kind == kind {
                if let role = Self.role(of: row, command: command, in: definition) {
                    return AgentMatch(definition: definition, role: role)
                }
            }
            return nil
        }
        if let match = firstMatch(.desktop) { return match }
        if row.executablePath.contains(".app/Contents/"), !command.interpreterRunsScript { return nil }
        if let match = firstMatch(.cli) { return match }
        for name in userNames where command.names.contains(name.lowercased()) {
            return AgentMatch(definition: Self.userDefinition(name: name), role: .session)
        }
        return nil
    }

    /// One instance per session, engine or possible session. A matched
    /// process is not a new instance when it only continues another one:
    /// a session whose direct parent is a session of the same agent (a
    /// launcher that starts the real binary), or an engine below an engine
    /// of the same agent. A session that a shell or a helper started is its
    /// own instance. Each instance's rows stop where another instance starts,
    /// so the same work is never counted on two instances.
    func instances(in snapshot: [ProcessInfoRow], userNames: [String] = []) -> [AgentInstance] {
        var matches: [Int32: AgentMatch] = [:]
        for row in snapshot {
            if let match = match(row, userNames: userNames) { matches[row.pid] = match }
        }
        return instances(in: snapshot, matches: matches)
    }

    /// For a caller that keeps the match of each process from one snapshot
    /// to the next. `matches` is by pid and holds every matched process.
    func instances(in snapshot: [ProcessInfoRow], matches: [Int32: AgentMatch]) -> [AgentInstance] {
        let byPID = Dictionary(snapshot.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = snapshot.filter { row in
            guard let match = matches[row.pid] else { return false }
            return Self.isRoot(row, match: match, matches: matches, byPID: byPID)
        }
        let rootPIDs = Set(roots.map(\.pid))
        let children = ProcessCensus.childrenIndex(of: snapshot)
        return roots.compactMap { root in
            guard let match = matches[root.pid] else { return nil }
            return AgentInstance(
                definition: match.definition,
                role: match.role,
                rootPID: root.pid,
                rootStartTime: root.startTime,
                rows: ProcessCensus.subtree(of: root, in: children, stoppingAt: rootPIDs)
            )
        }
    }

    private static func isRoot(_ row: ProcessInfoRow, match: AgentMatch, matches: [Int32: AgentMatch], byPID: [Int32: ProcessInfoRow]) -> Bool {
        switch match.role {
        case .helper:
            return false
        case .helperMaybeSession:
            return true
        case .session:
            guard row.ppid != row.pid, let parent = matches[row.ppid] else { return true }
            return parent.definition.id != match.definition.id || parent.role == .helper || parent.role == .engine
        case .engine:
            var visited: Set<Int32> = [row.pid]
            var pid = row.ppid
            while visited.insert(pid).inserted, let ancestor = byPID[pid] {
                if let above = matches[pid], above.role == .engine, above.definition.id == match.definition.id { return false }
                pid = ancestor.ppid
            }
            return true
        }
    }

    private static func role(of row: ProcessInfoRow, command: Command, in definition: AgentDefinition) -> AgentRole? {
        let matched = definition.matchers.contains { matcher in
            matches(matcher.process, row: row, command: command) && matches(matcher.arguments, command: command)
                && !matcher.unless.contains { matches($0, command: command) }
        }
        for exclusion in definition.exclusions {
            let processMatches = exclusion.process.map { matches($0, row: row, command: command) } ?? matched
            if processMatches && matches(exclusion.arguments, command: command) { return exclusion.role }
        }
        guard matched else { return nil }
        return definition.kind == .desktop ? .engine : .session
    }

    private static func matches(_ matcher: ProcessMatcher, row: ProcessInfoRow, command: Command) -> Bool {
        switch matcher {
        case .name(let name):
            return command.names.contains(name.lowercased())
        case .executableSuffix(let suffix):
            return row.executablePath.hasSuffix(suffix)
        case .executableContains(let part):
            return row.executablePath.contains(part)
        case .executable(let part, let title):
            guard row.executablePath.contains(part) else { return false }
            let name = baseName(row.arguments.first ?? "").lowercased()
            return name.isEmpty || name.hasPrefix(title) || name == baseName(row.executablePath).lowercased()
        case .appBundle(let bundle, let relativePath):
            if let bundle { return row.executablePath.hasSuffix("/\(bundle)/\(relativePath)") }
            return row.executablePath.hasSuffix(".app/\(relativePath)")
        }
    }

    private static func matches(_ pattern: ArgumentPattern, command: Command) -> Bool {
        switch pattern {
        case .any:
            return true
        case .leading(let leading):
            return command.arguments.starts(with: leading)
        case .contains(let wanted):
            return wanted.allSatisfy(command.arguments.contains)
        case .anySuffix(let suffix):
            return command.arguments.contains { $0.hasSuffix(suffix) }
        case .firstIsOne(let words):
            return command.arguments.first.map(words.contains) ?? false
        case .oneFile(let extensions):
            guard command.arguments.count == 1, let file = command.arguments.first, !file.hasPrefix("-") else { return false }
            let name = baseName(file)
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
            return extensions.contains(name[name.index(after: dot)...].lowercased())
        }
    }

    private static func baseName(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    private static func isInterpreter(_ name: String) -> Bool {
        ["node", "bun", "deno", "ruby"].contains(name) || name.hasPrefix("python") || name.hasPrefix("pypy")
    }
}
