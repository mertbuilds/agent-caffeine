import XCTest

final class AgentCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let catalog = AgentCatalog.standard
    private let claudeBinary = "/Users/me/.local/share/claude/versions/2.1.289"
    private let codexBinary = "/Users/me/.codex/packages/standalone/current/bin/codex"
    private let codexDaemonBinary = "/Users/me/.codex/packages/app-server-daemon/releases/0.159.2-aarch64/bin/codex"
    private let chatGPT = "/Applications/ChatGPT.app/Contents"
    private let antigravity = "/Applications/Antigravity.app/Contents"

    private let homebrewPython = "/opt/homebrew/Cellar/python@3.14/3.14.0/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python"
    private let xcodePython = "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"

    private var codexDesktopBinary: String { "\(chatGPT)/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex" }

    // MARK: match

    /// Shapes copied from `ps` on a Mac with these agents running, with the
    /// home directory made generic. Nil id means no agent process.
    func testMatch() {
        let cases: [(name: String, path: String, args: [String], id: String?, role: AgentRole?)] = [
            // Claude Code. The short process name is the version number.
            ("claude interactive", claudeBinary, ["claude", "--dangerously-skip-permissions"], "claude", .session),
            ("claude resume", claudeBinary, ["claude", "--dangerously-skip-permissions", "--resume", "7c1e4a90-2b6d-4f38-9e15-0a3d5c7b9e24"], "claude", .session),
            ("claude headless by full path", claudeBinary, ["/Users/me/.local/bin/claude", "-p", "--model", "sonnet", "say hi"], "claude", .session),
            ("claude with a rewritten argv", claudeBinary, ["2.1.289"], "claude", .session),
            ("claude daemon supervisor", claudeBinary, ["/Users/me/.local/bin/claude", "daemon", "run", "--origin", "transient", "--spawned-by", "{\"label\":\"claude\",\"cwd\":\"/Users/me/wiki\",\"pid\":93968}"], "claude", .helper),
            ("claude pty host", claudeBinary, ["claude", "bg-pty-host", "--bg-pty-host", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.pty.sock", "200", "50", "--", claudeBinary, "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.claim.sock"], "claude", .helper),
            ("claude spare, claimed or warm", claudeBinary, ["claude", "bg-spare", "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/17dea89c.claim.sock"], "claude", .helperMaybeSession),
            // As KERN_PROCARGS2 gives them: the title is one argv[0].
            ("claude pty host, title in argv[0]", claudeBinary, ["claude bg-pty-host", "--bg-pty-host", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.pty.sock", "200", "50", "--", claudeBinary, "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.claim.sock"], "claude", .helper),
            ("claude spare, title in argv[0]", claudeBinary, ["claude bg-spare", "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/17dea89c.claim.sock"], "claude", .helperMaybeSession),
            ("claude told to work on a daemon", claudeBinary, ["claude", "-p", "daemon", "run"], "claude", .session),
            // Seen 2026-10-05: the Grep tool runs the Claude Code binary as ugrep.
            ("claude binary as its own search tool", claudeBinary, ["ugrep", "-G", "--ignore-files", "--hidden", "TODO"], nil, nil),
            ("claude desktop app", "/Applications/Claude.app/Contents/MacOS/Claude", ["/Applications/Claude.app/Contents/MacOS/Claude"], nil, nil),
            ("claude helper in a bundle with spaces", "/Users/me/My Apps/Claude.app/Contents/Helpers/claude", ["/Users/me/My Apps/Claude.app/Contents/Helpers/claude", "--stdio"], nil, nil),
            ("claude with a bundle path as argument", "/usr/local/bin/claude", ["/usr/local/bin/claude", "/Applications/Foo.app/Contents/x"], "claude", .session),

            // Codex CLI.
            ("codex TUI", codexBinary, ["codex", "--dangerously-bypass-approvals-and-sandbox"], "codex", .session),
            ("codex exec", codexBinary, ["codex", "exec", "--skip-git-repo-check", "sleep 20 then write 250 words"], "codex", .session),
            ("codex managed daemon", codexDaemonBinary, [codexDaemonBinary, "app-server", "--listen", "unix://", "--managed-daemon"], "codex", .engine),
            ("codex daemon pid loop", codexDaemonBinary, [codexDaemonBinary, "app-server", "daemon", "pid-update-loop"], "codex", .helper),
            ("codex exec-server", codexBinary, ["codex", "exec-server"], "codex", .helper),
            ("codex IDE extension app-server", "/Users/me/.vscode/extensions/openai.chatgpt-0.4.1/bin/macos-aarch64/codex", ["/Users/me/.vscode/extensions/openai.chatgpt-0.4.1/bin/macos-aarch64/codex", "app-server", "--analytics-default-enabled"], "codex", .helper),
            ("codex code mode host", "/Users/me/.local/bin/codex-code-mode-host", ["codex-code-mode-host"], "codex", .helper),
            ("codex prompt that names app-server", codexBinary, ["codex", "fix the app-server crash"], "codex", .session),
            ("codex through node", "/opt/homebrew/bin/node", ["node", "/opt/homebrew/bin/codex", "exec-server"], "codex", .helper),

            // Codex desktop, inside ChatGPT.app.
            ("codex desktop engine", codexDesktopBinary, [codexDesktopBinary, "-c", "features.code_mode_host=true", "app-server", "--analytics-default-enabled"], "codex-desktop", .engine),
            ("codex desktop stdio engine", codexDesktopBinary, [codexDesktopBinary, "app-server", "--listen", "stdio://"], "codex-desktop", .engine),
            ("codex desktop exec-server", codexDesktopBinary, [codexDesktopBinary, "exec-server", "--remote", "https://codex-cloud-environments.chatgpt.com/api", "--environment-id", "ccarenv_x"], "codex-desktop", .helper),
            ("codex desktop code mode host", "\(chatGPT)/Resources/codex-cli/bin/codex-code-mode-host", ["\(chatGPT)/Resources/codex-cli/bin/codex-code-mode-host"], "codex-desktop", .helper),
            ("codex desktop binary without app-server", codexDesktopBinary, [codexDesktopBinary, "login"], nil, nil),
            ("codex desktop in a renamed bundle", "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", ["codex", "app-server"], "codex-desktop", .engine),
            ("ChatGPT main", "\(chatGPT)/MacOS/ChatGPT", ["\(chatGPT)/MacOS/ChatGPT"], nil, nil),
            ("ChatGPT renderer", "\(chatGPT)/Frameworks/Codex Framework.framework/Versions/154.0.8037.57/Helpers/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)", ["\(chatGPT)/Frameworks/Codex Framework.framework/Versions/154.0.8037.57/Helpers/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)", "--type=renderer"], nil, nil),
            ("ChatGPT node_repl", "\(chatGPT)/Resources/cua_node/bin/node_repl", ["\(chatGPT)/Resources/cua_node/bin/node_repl"], nil, nil),
            ("ChatGPT node script", "\(chatGPT)/Resources/cua_node/bin/node", ["\(chatGPT)/Resources/cua_node/bin/node", "./server.mjs"], nil, nil),
            ("ChatGPT updater", "\(chatGPT)/Frameworks/Sparkle.framework/Versions/B/Autoupdate", ["\(chatGPT)/Frameworks/Sparkle.framework/Versions/B/Autoupdate", "com.openai.codex", "/Users/me", "me"], nil, nil),
            ("Codex computer use service", "/Users/me/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService", ["/Users/me/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService"], nil, nil),

            // Antigravity.
            ("antigravity engine", "\(antigravity)/Resources/bin/language_server", ["\(antigravity)/Resources/bin/language_server", "--standalone", "--override_ide_name", "antigravity", "--subclient_type", "hub"], "antigravity-desktop", .engine),
            ("antigravity main", "\(antigravity)/MacOS/Antigravity", ["\(antigravity)/MacOS/Antigravity"], nil, nil),
            ("antigravity helper", "\(antigravity)/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper", ["\(antigravity)/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper", "--type=gpu-process"], nil, nil),
            ("antigravity video encoder", "\(antigravity)/Resources/bin/webm_encoder", ["\(antigravity)/Resources/bin/webm_encoder"], nil, nil),
            ("language_server of another app", "/Applications/Other.app/Contents/Resources/bin/language_server", ["/Applications/Other.app/Contents/Resources/bin/language_server"], nil, nil),

            // Other CLIs.
            ("opencode run", "/Users/me/.opencode/bin/opencode", ["/Users/me/.opencode/bin/opencode", "run", "say hi"], "opencode", .session),
            ("droid exec", "/Users/me/.local/bin/droid", ["droid", "exec", "--auto", "low", "say hi"], "droid", .session),
            ("grok headless", "/Users/me/.grok/bin/grok", ["grok", "--always-approve", "-p", "say hi"], "grok", .session),
            ("gemini with a process title", "/opt/homebrew/bin/node", ["gemini"], "gemini", .session),
            ("gemini script run by node", "/opt/homebrew/Cellar/node/24.1.0/bin/node", ["node", "--no-warnings", "/opt/homebrew/bin/gemini", "-p", "hi"], "gemini", .session),
            ("gemini-cli alias", "/opt/homebrew/bin/node", ["node", "/opt/homebrew/bin/gemini-cli"], "gemini", .session),
            ("pi script run by bun", "/Users/me/.bun/bin/bun", ["bun", "/Users/me/.bun/bin/pi.js"], "pi", .session),
            // The kernel reports the resolved binary, and the Python of
            // Homebrew and of Xcode is inside a Python.app.
            ("aider run by Homebrew python", homebrewPython, ["/opt/homebrew/Cellar/aider/0.86.1/libexec/bin/python", "/opt/homebrew/bin/aider", "--model", "sonnet"], "aider", .session),
            ("aider run by Xcode python", xcodePython, ["/usr/bin/python3", "/Users/me/Library/Python/3.9/bin/aider"], "aider", .session),
            ("aider run by a python outside a bundle", "/Users/me/.pyenv/versions/3.12.4/bin/python3.12", ["python3", "/Users/me/.pyenv/shims/aider"], "aider", .session),
            ("openhands run by ruby in a bundle", "/Applications/Tool.app/Contents/Resources/ruby", ["ruby", "/usr/local/bin/openhands"], "openhands", .session),
            ("framework python at its prompt", homebrewPython, ["python3"], nil, nil),
            ("framework python with another script", homebrewPython, ["python3", "/Users/me/code/server.py"], nil, nil),
            ("bundle helper named like an agent, with a script", "/Applications/Foo.app/Contents/MacOS/aider", ["aider", "/usr/local/bin/aider"], nil, nil),
            ("uppercase argv[0]", "/usr/local/bin/Goose", ["Goose", "session"], "goose", .session),

            // Not agents.
            ("node server", "/opt/homebrew/bin/node", ["/opt/homebrew/bin/node", "server.js"], nil, nil),
            ("shell that runs an agent command", "/bin/zsh", ["/bin/zsh", "-c", "claude -p hi"], nil, nil),
            ("tool that names an agent", "/usr/bin/tail", ["tail", "-f", "/Users/me/.codex/log/codex.log"], nil, nil),
            ("herdr multiplexer", "/Users/me/.local/bin/herdr", ["herdr", "server"], nil, nil),
            ("caffeinate child", "/usr/bin/caffeinate", ["caffeinate", "-i", "-t", "300"], nil, nil),
            ("system cursor service", "/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService", ["/System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService"], nil, nil),
            ("zombie without arguments", "/usr/bin/true", [], nil, nil),
        ]
        for (index, testCase) in cases.enumerated() {
            let match = catalog.match(.fixture(Int32(index + 10), path: testCase.path, args: testCase.args), userNames: [])
            XCTAssertEqual(match?.definition.id, testCase.id, testCase.name)
            XCTAssertEqual(match?.role, testCase.role, testCase.name)
        }
    }

    func testUserNamesMatchAtGenericLevel() {
        let mine: Row = .fixture(10, path: "/Users/me/bin/myagent", args: ["myagent", "--work"])
        XCTAssertNil(catalog.match(mine, userNames: []))
        let match = catalog.match(mine, userNames: ["claude", "MyAgent"])
        XCTAssertEqual(match?.definition.id, "user:MyAgent")
        XCTAssertEqual(match?.definition.level, .generic)
        XCTAssertEqual(match?.definition.kind, .cli)
        XCTAssertEqual(match?.role, .session)

        // A catalog agent keeps its definition and its exclusions when its
        // name is also in the user's list.
        let claude: Row = .fixture(11, path: claudeBinary, args: ["claude"])
        XCTAssertEqual(catalog.match(claude, userNames: ["claude"])?.definition.level, .state)
        let host: Row = .fixture(12, path: claudeBinary, args: ["claude", "bg-pty-host", "--bg-pty-host", "/tmp/x.pty.sock"])
        XCTAssertEqual(catalog.match(host, userNames: ["claude"])?.role, .helper)

        // A user name does not reach into app bundles either.
        let bundled: Row = .fixture(13, path: "/Applications/MyAgent.app/Contents/MacOS/myagent", args: ["myagent"])
        XCTAssertNil(catalog.match(bundled, userNames: ["myagent"]))
    }

    // MARK: catalog data

    /// The names the app matched before it had a catalog. A saved name list
    /// is migrated against the catalog, so each of them has to stay in it.
    func testCatalogCoversTheOldAllowlist() {
        let oldAllowlist = [
            "aider", "aider-desk", "amp", "antigravity", "augment", "claude", "cline", "cn", "codearts-agent", "codebuddy",
            "codemaker", "codestudio", "codex", "command-code", "copilot", "crush", "cursor-agent", "deepagents", "devin",
            "dexto", "droid", "firebender", "forgecode", "gemini", "gemini-cli", "goose", "grok", "hermes-agent", "iflow-cli",
            "junie", "kilo", "kiro-cli", "mcpjam", "mistral-vibe", "neovate", "opencode", "openclaw", "openhands", "pi",
            "pochi", "qoder", "qwen-code", "rovodev", "tabnine-cli", "trae", "trae-cn", "windsurf", "zencoder",
        ]
        XCTAssertEqual(Set(oldAllowlist).subtracting(catalog.cliNames), [])
        for name in oldAllowlist {
            let match = catalog.match(.fixture(10, path: "/usr/local/bin/\(name)", args: [name]), userNames: [])
            XCTAssertEqual(match?.role, .session, name)
            XCTAssertEqual(match?.definition.kind, .cli, name)
        }
    }

    func testCatalogLevelsAndIds() {
        let ids = catalog.definitions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let stateIDs = catalog.definitions.filter { $0.level == .state }.map(\.id)
        XCTAssertEqual(Set(stateIDs), ["claude", "codex", "codex-desktop"])
        XCTAssertFalse(catalog.definitions.contains { $0.level == .generic })
        // Placeholders match nothing and say so.
        for id in ["claude-desktop", "t3-code", "cursor-desktop"] {
            let definition = catalog.definitions.first { $0.id == id }
            XCTAssertEqual(definition?.kind, .desktop, id)
            XCTAssertEqual(definition?.verified, false, id)
            XCTAssertEqual(definition?.matchers, [], id)
        }
        XCTAssertEqual(catalog.definitions.first { $0.id == "antigravity-desktop" }?.verified, true)
    }

    func testCommand() {
        let node = AgentCatalog.command(of: .fixture(10, path: "/opt/homebrew/bin/node", args: ["node", "--no-warnings", "/opt/homebrew/bin/gemini.js", "-p", "hi"]))
        XCTAssertEqual(node.names, ["node", "gemini"])
        XCTAssertEqual(node.arguments, ["-p", "hi"])
        let claude = AgentCatalog.command(of: .fixture(11, path: claudeBinary, args: ["/Users/me/.local/bin/claude", "daemon", "run"]))
        XCTAssertEqual(claude.names, ["claude", "2.1.289"])
        XCTAssertEqual(claude.arguments, ["daemon", "run"])
        XCTAssertEqual(AgentCatalog.command(of: .fixture(12, path: "", args: [])), AgentCatalog.Command(names: [], arguments: []))
    }

    func testExecutableSuffixMatcher() {
        let custom = AgentCatalog(definitions: [
            AgentDefinition(id: "x", displayName: "X", level: .activity, kind: .cli, matchers: [AgentMatcher(.executableSuffix("/libexec/x-agent"), arguments: .leading(["serve"]))], exclusions: [], verified: false),
        ])
        XCTAssertEqual(custom.match(.fixture(10, path: "/opt/x/libexec/x-agent", args: ["renamed", "serve", "--port", "1"]), userNames: [])?.definition.id, "x")
        XCTAssertNil(custom.match(.fixture(11, path: "/opt/x/libexec/x-agent", args: ["renamed", "--port", "1", "serve"]), userNames: []))
        XCTAssertNil(custom.match(.fixture(12, path: "/opt/x/libexec/x-agent-helper", args: ["renamed", "serve"]), userNames: []))
    }

    // MARK: instances

    private func ids(_ instances: [AgentInstance]) -> [String] {
        instances.map { "\($0.definitionID):\($0.rootPID)" }
    }

    /// The Claude Code daemon family as measured: an interactive session
    /// starts the daemon, the daemon keeps pty hosts, each host owns a spare.
    func testClaudeDaemonFamilyGivesNoPhantomAgents() {
        let spareArgs = ["claude", "bg-spare", "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.claim.sock"]
        let hostArgs = ["claude", "bg-pty-host", "--bg-pty-host", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.pty.sock", "200", "50", "--", claudeBinary, "--bg-spare", "/tmp/cc-daemon-501/03c1f701/spare/025596a1.claim.sock"]
        let snapshot: [Row] = [
            .fixture(93890, path: "/bin/zsh", args: ["-zsh"]),
            .fixture(93968, ppid: 93890, path: claudeBinary, args: ["claude", "--dangerously-skip-permissions"], tty: 0x1000_0009),
            .fixture(19184, ppid: 93968, path: "/bin/zsh", args: ["/bin/zsh", "-c", "git status"]),
            .fixture(20909, ppid: 93968, path: claudeBinary, args: ["/Users/me/.local/bin/claude", "daemon", "run", "--origin", "transient"]),
            .fixture(20930, ppid: 20909, path: claudeBinary, args: hostArgs),
            .fixture(20946, ppid: 20930, path: claudeBinary, args: spareArgs, tty: 0x1000_000d),
            .fixture(32924, ppid: 20946, path: "/usr/bin/caffeinate", args: ["caffeinate", "-i", "-t", "300"]),
            .fixture(33001, ppid: 20946, path: "/bin/zsh", args: ["zsh", "-c", "xcodebuild test"]),
            .fixture(33002, ppid: 33001, path: "/usr/bin/xcodebuild", args: ["xcodebuild", "test"]),
            .fixture(21510, ppid: 20909, path: claudeBinary, args: hostArgs),
            .fixture(21523, ppid: 21510, path: claudeBinary, args: spareArgs),
            .fixture(2422, ppid: 2514, path: "/Users/me/.local/share/claude/versions/2.1.288", args: ["claude", "--resume", "a56cc820"], tty: 0x1000_0001),
        ]
        let instances = catalog.instances(in: snapshot)
        XCTAssertEqual(ids(instances), ["claude:93968", "claude:20946", "claude:21523", "claude:2422"])
        XCTAssertEqual(instances.map(\.role), [.session, .helperMaybeSession, .helperMaybeSession, .session])
        // The session keeps its helpers, and the spares' work is not counted on it.
        XCTAssertEqual(instances[0].rows.map(\.pid), [93968, 19184, 20909, 20930, 21510])
        XCTAssertEqual(instances[1].rows.map(\.pid), [20946, 32924, 33001, 33002])
        XCTAssertEqual(instances[2].rows.map(\.pid), [21523])
        XCTAssertEqual(instances[3].rows.map(\.pid), [2422])
        XCTAssertEqual(instances[1].identity, snapshot[5].identity)
    }

    func testOrphanedClaudeDaemonIsNoInstance() {
        let snapshot: [Row] = [
            .fixture(20909, path: claudeBinary, args: ["claude", "daemon", "run"]),
            .fixture(20930, ppid: 20909, path: claudeBinary, args: ["claude", "bg-pty-host", "--bg-pty-host", "/tmp/a.pty.sock"]),
        ]
        XCTAssertEqual(catalog.instances(in: snapshot), [])
    }

    /// A Codex TUI starts the managed daemon as its child. The daemon runs
    /// the tools, stays alive with ppid 1 after the TUI exits, and a second
    /// TUI reuses it.
    func testCodexManagedDaemonIsItsOwnInstance() {
        let daemonArgs = [codexDaemonBinary, "app-server", "--listen", "unix://", "--managed-daemon"]
        let withTUI: [Row] = [
            .fixture(48500, path: codexBinary, args: ["codex", "sleep 15 then write 120 words"], tty: 0x1000_0003),
            .fixture(48605, ppid: 48500, path: codexDaemonBinary, args: daemonArgs),
            .fixture(48631, ppid: 48605, path: codexDaemonBinary, args: [codexDaemonBinary, "app-server", "daemon", "pid-update-loop"]),
            .fixture(48700, ppid: 48605, path: "/Users/me/.local/bin/codex-code-mode-host", args: ["codex-code-mode-host"]),
            .fixture(48701, ppid: 48605, path: "/bin/sleep", args: ["sleep", "15"]),
            .fixture(48900, path: codexBinary, args: ["codex"], tty: 0x1000_0004),
        ]
        let instances = catalog.instances(in: withTUI)
        XCTAssertEqual(ids(instances), ["codex:48500", "codex:48605", "codex:48900"])
        XCTAssertEqual(instances.map(\.role), [.session, .engine, .session])
        XCTAssertEqual(instances[0].rows.map(\.pid), [48500])
        XCTAssertEqual(instances[1].rows.map(\.pid), [48605, 48631, 48700, 48701])

        let leftover: [Row] = [
            .fixture(48605, path: codexDaemonBinary, args: daemonArgs),
            .fixture(48631, ppid: 48605, path: codexDaemonBinary, args: [codexDaemonBinary, "app-server", "daemon", "pid-update-loop"]),
        ]
        let alone = catalog.instances(in: leftover)
        XCTAssertEqual(ids(alone), ["codex:48605"])
        XCTAssertEqual(alone.first?.role, .engine)
    }

    func testCodexDesktopIsOneEngine() {
        let node = "\(chatGPT)/Resources/cua_node/bin/node"
        let snapshot: [Row] = [
            .fixture(25328, path: "\(chatGPT)/MacOS/ChatGPT", args: ["\(chatGPT)/MacOS/ChatGPT"]),
            .fixture(25445, ppid: 25328, path: codexDesktopBinary, args: [codexDesktopBinary, "-c", "features.code_mode_host=true", "app-server", "--analytics-default-enabled"]),
            .fixture(25852, ppid: 25445, path: node, args: [node, "\(chatGPT)/Resources/cua_node/lib/node_modules/@oai/cua-repl/bin/cua-repl.mjs"]),
            .fixture(25854, ppid: 25852, path: "\(chatGPT)/Resources/cua_node/bin/node_repl", args: ["\(chatGPT)/Resources/cua_node/bin/node_repl"]),
            .fixture(27648, ppid: 25854, path: codexDesktopBinary, args: [codexDesktopBinary, "app-server", "--listen", "stdio://"]),
            .fixture(45334, ppid: 25445, path: "\(chatGPT)/Resources/codex-cli/bin/codex-code-mode-host", args: ["\(chatGPT)/Resources/codex-cli/bin/codex-code-mode-host"]),
            .fixture(29747, ppid: 25328, path: codexDesktopBinary, args: [codexDesktopBinary, "exec-server", "--remote", "https://codex-cloud-environments.chatgpt.com/api"]),
            .fixture(69955, ppid: 25328, path: "\(chatGPT)/Frameworks/Codex Framework.framework/Versions/154.0.8037.57/Helpers/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)", args: ["Codex (Renderer)", "--type=renderer"]),
            .fixture(99153, path: "\(antigravity)/MacOS/Antigravity", args: ["\(antigravity)/MacOS/Antigravity"]),
            .fixture(99271, ppid: 99153, path: "\(antigravity)/Resources/bin/language_server", args: ["\(antigravity)/Resources/bin/language_server", "--standalone"]),
        ]
        let instances = catalog.instances(in: snapshot)
        XCTAssertEqual(ids(instances), ["codex-desktop:25445", "antigravity-desktop:99271"])
        XCTAssertEqual(instances.map(\.role), [.engine, .engine])
        XCTAssertEqual(instances[0].rows.map(\.pid), [25445, 25852, 25854, 27648, 45334])
    }

    func testNestedSessions() {
        let snapshot: [Row] = [
            // A launcher that starts the real binary is one agent.
            .fixture(100, path: "/opt/homebrew/bin/node", args: ["node", "/opt/homebrew/bin/codex"]),
            .fixture(101, ppid: 100, path: "/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex", args: ["/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex"]),
            // A headless run that a session starts through its shell tool is its own session.
            .fixture(200, path: claudeBinary, args: ["claude"]),
            .fixture(201, ppid: 200, path: "/bin/zsh", args: ["/bin/zsh", "-c", "claude -p 'review this'"]),
            .fixture(202, ppid: 201, path: claudeBinary, args: ["claude", "-p", "review this"]),
            // A different agent directly below a session is its own agent.
            .fixture(203, ppid: 200, path: codexBinary, args: ["codex", "exec", "hi"]),
            .fixture(300, path: "/Users/me/bin/myagent", args: ["myagent"]),
        ]
        let instances = catalog.instances(in: snapshot, userNames: ["myagent"])
        XCTAssertEqual(ids(instances), ["codex:100", "claude:200", "claude:202", "codex:203", "user:myagent:300"])
        XCTAssertEqual(instances[0].rows.map(\.pid), [100, 101])
        XCTAssertEqual(instances[1].rows.map(\.pid), [200, 201])
        XCTAssertEqual(instances[4].definition.level, .generic)
    }

    func testReusedRootPidIsANewInstanceIdentity() {
        let first = catalog.instances(in: [.fixture(500, start: 1_791_000_000, path: claudeBinary, args: ["claude"])])
        let second = catalog.instances(in: [.fixture(500, start: 1_791_000_900.5, path: claudeBinary, args: ["claude"])])
        XCTAssertEqual(first.first?.rootPID, second.first?.rootPID)
        XCTAssertNotEqual(first.first?.identity, second.first?.identity)
    }
}
