import XCTest

/// Stands in for `NSRunningApplication`: these pids are apps with windows.
private struct FakeApps: AgentHostApps {
    var regular: Set<Int32>

    func isRegularApp(_ pid: Int32) -> Bool { regular.contains(pid) }
}

final class AgentHostTests: XCTestCase {
    typealias Row = ProcessInfoRow

    private let claude = "/Users/me/.local/share/claude/versions/2.1.0"
    private let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    private let ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    private let cursor = "/Applications/Cursor.app/Contents/MacOS/Cursor"
    private let tmux = "/opt/homebrew/Cellar/tmux/3.5a/bin/tmux"

    private func resolve(_ pid: Int32, _ kind: AgentDefinition.Kind = .cli, in rows: [Row], apps: Set<Int32>) -> AgentHost? {
        AgentHostResolver.resolve(pid: pid, kind: kind, table: AgentHostTable(rows: rows), apps: FakeApps(regular: apps))
    }

    /// A shell with an agent in it, below `parent`.
    private func session(shell: Int32, agent: Int32, parent: Int32, tty: Int32) -> [Row] {
        [
            .fixture(shell, ppid: parent, path: "/bin/zsh", tty: tty),
            .fixture(agent, ppid: shell, path: claude, tty: tty),
        ]
    }

    func testADesktopAgentIsItsOwnApp() {
        let rows: [Row] = [
            .fixture(100, path: cursor),
            .fixture(101, ppid: 100, path: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Renderer).app/Contents/MacOS/Cursor Helper (Renderer)"),
        ]
        XCTAssertEqual(resolve(100, .desktop, in: rows, apps: [100]), AgentHost(appPid: 100))
    }

    func testTheEngineOfADesktopAppGoesToTheApp() {
        let rows: [Row] = [
            .fixture(100, path: "/Applications/Codex.app/Contents/MacOS/Codex"),
            .fixture(101, ppid: 100, path: "/Applications/Codex.app/Contents/Resources/codex", args: ["codex", "app-server"]),
            // Its parent is gone, so launchd is above it.
            .fixture(102, ppid: 1, path: "/Applications/Codex.app/Contents/Resources/codex", args: ["codex", "app-server"]),
        ]
        XCTAssertEqual(resolve(101, .desktop, in: rows, apps: [100])?.appPid, 100)
        XCTAssertEqual(resolve(102, .desktop, in: rows, apps: [100])?.appPid, 100, "By the bundle it lies in")
    }

    func testACommandLineAgentGoesToItsTerminal() {
        // `login` belongs to root and is above the shell.
        let rows: [Row] = [.fixture(20, path: terminal), .fixture(30, ppid: 20, path: "/usr/bin/login", tty: 7)]
            + session(shell: 31, agent: 40, parent: 30, tty: 7)
        XCTAssertEqual(resolve(40, in: rows, apps: [20]), AgentHost(appPid: 20, tty: 7))
        XCTAssertEqual(resolve(40, in: rows.map { $0.pid == 20 ? .fixture(20, path: ghostty) : $0 }, apps: [20])?.appPid, 20, "Any app with windows")
    }

    func testAnAgentInTheTerminalOfCursorGoesToCursor() {
        let helper = "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)"
        let rows: [Row] = [.fixture(100, path: cursor), .fixture(110, ppid: 100, path: helper)]
            + session(shell: 120, agent: 130, parent: 110, tty: 9)
        XCTAssertEqual(resolve(130, in: rows, apps: [100]), AgentHost(appPid: 100, tty: 9))
        // The helper lost its parent.
        let orphaned = rows.map { $0.pid == 110 ? Row.fixture(110, ppid: 1, path: helper) : $0 }
        XCTAssertEqual(resolve(130, in: orphaned, apps: [100])?.appPid, 100, "The helper belongs to the app it lies in")
    }

    func testAnAgentInTheTerminalOfVisualStudioCodeGoesToIt() {
        let code = "/Applications/Visual Studio Code.app/Contents"
        let rows: [Row] = [
            .fixture(200, path: "\(code)/MacOS/Electron"),
            .fixture(210, ppid: 1, path: "\(code)/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
            // Another app runs too.
            .fixture(100, path: cursor),
        ] + session(shell: 220, agent: 230, parent: 210, tty: 3)
        XCTAssertEqual(resolve(230, in: rows, apps: [100, 200])?.appPid, 200)
    }

    func testTwoCopiesOfTheAppOfAnOrphanedHelperGiveNoApp() {
        let code = "/Applications/Visual Studio Code.app/Contents"
        let rows: [Row] = [
            .fixture(200, path: "\(code)/MacOS/Electron"),
            .fixture(201, path: "\(code)/MacOS/Electron"),
            .fixture(210, ppid: 1, path: "\(code)/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
        ] + session(shell: 220, agent: 230, parent: 210, tty: 3)
        XCTAssertNil(resolve(230, in: rows, apps: [200, 201]))
    }

    func testACommandLineAgentIsNotTheAppItsBinaryLiesIn() {
        let rows: [Row] = [
            .fixture(100, path: "/Applications/Codex.app/Contents/MacOS/Codex"),
            .fixture(20, path: terminal),
            .fixture(31, ppid: 20, path: "/bin/zsh", tty: 7),
            .fixture(40, ppid: 31, path: "/Applications/Codex.app/Contents/Resources/codex", tty: 7),
            // Over SSH, with the same binary.
            .fixture(50, ppid: 1, path: "/usr/sbin/sshd"),
            .fixture(51, ppid: 50, path: "/bin/zsh", tty: 8),
            .fixture(60, ppid: 51, path: "/Applications/Codex.app/Contents/Resources/codex", tty: 8),
        ]
        XCTAssertEqual(resolve(40, in: rows, apps: [20, 100])?.appPid, 20)
        XCTAssertNil(resolve(60, in: rows, apps: [20, 100]), "It runs in no app of this Mac")
    }

    func testAnAgentInITermGoesToITermThroughItsServer() {
        let rows: [Row] = [
            .fixture(20, path: "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
            .fixture(25, ppid: 1, path: "/Users/me/Library/Application Support/iTerm2/iTermServer-3.5.14"),
            .fixture(30, ppid: 25, path: "/usr/bin/login", tty: 7),
        ] + session(shell: 31, agent: 40, parent: 30, tty: 7)
        XCTAssertEqual(resolve(40, in: rows, apps: [20]), AgentHost(appPid: 20, tty: 7))
        XCTAssertNil(resolve(40, in: rows, apps: []), "iTerm2 does not run")
    }

    // MARK: tmux

    /// A tmux server with an agent in a pane, and a client in each of the
    /// given terminals: pid of the app, then the terminal device of the tab.
    private func tmuxRows(clients: [(app: Int32, tty: Int32)]) -> [Row] {
        var rows: [Row] = [.fixture(300, ppid: 1, path: tmux)] + session(shell: 310, agent: 320, parent: 300, tty: 50)
        for (index, client) in clients.enumerated() {
            let shell = Int32(400 + index * 10)
            rows += [
                .fixture(shell, ppid: client.app, path: "/bin/zsh", tty: client.tty),
                .fixture(shell + 1, ppid: shell, path: tmux, args: ["tmux", "attach"], tty: client.tty),
            ]
        }
        return rows + [.fixture(20, path: terminal), .fixture(21, path: ghostty)]
    }

    func testTmuxWithOneClientGoesToTheTerminalOfTheClient() {
        let host = resolve(320, in: tmuxRows(clients: [(app: 20, tty: 7)]), apps: [20, 21])
        XCTAssertEqual(host, AgentHost(appPid: 20, tty: 50, clientTTY: 7), "The pane of the agent, and the tab of the client")
    }

    func testTmuxWithTwoClientsInOneAppGoesToThatApp() {
        let host = resolve(320, in: tmuxRows(clients: [(app: 20, tty: 7), (app: 20, tty: 8)]), apps: [20, 21])
        XCTAssertEqual(host, AgentHost(appPid: 20, tty: 50, clientTTY: nil), "Which tab is not known")
    }

    func testTmuxWithClientsInTwoAppsGivesNoApp() {
        XCTAssertNil(resolve(320, in: tmuxRows(clients: [(app: 20, tty: 7), (app: 21, tty: 8)]), apps: [20, 21]))
    }

    func testTmuxWithNoClientGivesNoApp() {
        XCTAssertNil(resolve(320, in: tmuxRows(clients: []), apps: [20, 21]), "Detached")
        // A client over SSH is in no app of this Mac, and a tmux command in a pane is no client.
        let rows = tmuxRows(clients: []) + [
            .fixture(50, ppid: 1, path: "/usr/sbin/sshd"),
            .fixture(51, ppid: 50, path: tmux, args: ["tmux", "attach"], tty: 9),
            .fixture(330, ppid: 310, path: tmux, args: ["tmux", "list-panes"], tty: 50),
        ]
        XCTAssertNil(resolve(320, in: rows, apps: [20, 21]))
    }

    func testHerdrHasTheShapeOfTmux() {
        let herdr = "/Users/me/.local/bin/herdr"
        let rows: [Row] = [
            .fixture(300, ppid: 1, path: herdr, args: ["herdr", "server"]),
            .fixture(21, path: ghostty),
            .fixture(30, ppid: 21, path: "/usr/bin/login", tty: 7),
            .fixture(31, ppid: 30, path: "/bin/zsh", tty: 7),
            .fixture(32, ppid: 31, path: herdr, tty: 7),
            // No client: it has no terminal.
            .fixture(33, ppid: 32, path: herdr, args: ["herdr", "remote-client-bridge"]),
            // A tmux client in another app shows another server.
            .fixture(20, path: terminal),
            .fixture(40, ppid: 20, path: tmux, args: ["tmux", "attach"], tty: 8),
        ] + session(shell: 310, agent: 320, parent: 300, tty: 50)
        XCTAssertEqual(resolve(320, in: rows, apps: [20, 21]), AgentHost(appPid: 21, tty: 50, clientTTY: 7))
    }

    // MARK: No app

    func testNoAppAboveGivesNoApp() {
        let ssh: [Row] = [.fixture(50, ppid: 1, path: "/usr/sbin/sshd"), .fixture(51, ppid: 50, path: "/usr/sbin/sshd")]
            + session(shell: 52, agent: 60, parent: 51, tty: 8)
        XCTAssertNil(resolve(60, in: ssh + [.fixture(20, path: terminal)], apps: [20]), "Over SSH")
        let screen: [Row] = [.fixture(70, ppid: 1, path: "/usr/bin/screen")] + session(shell: 71, agent: 80, parent: 70, tty: 8)
        XCTAssertNil(resolve(80, in: screen + [.fixture(20, path: terminal), .fixture(90, ppid: 20, path: "/usr/bin/screen", tty: 7)], apps: [20]), "Under screen")
        let zellij: [Row] = [.fixture(70, ppid: 1, path: "/opt/homebrew/bin/zellij")] + session(shell: 71, agent: 80, parent: 70, tty: 8)
        XCTAssertNil(resolve(80, in: zellij + [.fixture(20, path: terminal)], apps: [20]), "Under zellij")
    }

    func testAnAgentThatIsGoneGivesNoApp() {
        XCTAssertNil(resolve(999, in: [.fixture(20, path: terminal)], apps: [20]))
        XCTAssertNil(resolve(999, .desktop, in: [], apps: []))
    }

    func testAParentThatIsGoneAndALoopEndTheWayUp() {
        XCTAssertNil(resolve(40, in: [.fixture(40, ppid: 31, path: claude)], apps: [20]), "The shell is not in the table")
        XCTAssertNil(resolve(7, in: [.fixture(7, ppid: 7, path: claude)], apps: []), "No loop")
        let deep = (2...100).map { Row.fixture(Int32($0), ppid: Int32($0 - 1), path: "/bin/zsh") }
        XCTAssertNil(resolve(100, in: deep + [.fixture(1, ppid: 0, path: terminal)], apps: [2]), "Not deeper than the limit")
    }

    func testTheWholeTableIsReadOnlyWhenTheWayUpFindsNoApp() {
        let rows: [Row] = [.fixture(20, path: terminal)] + session(shell: 31, agent: 40, parent: 20, tty: 7)
        let index = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        var reads = 0
        let table = AgentHostTable(row: { index[$0] }, all: {
            reads += 1
            return rows
        })
        XCTAssertEqual(AgentHostResolver.resolve(pid: 40, kind: .cli, table: table, apps: FakeApps(regular: [20]))?.appPid, 20)
        XCTAssertEqual(reads, 0)
    }
}
