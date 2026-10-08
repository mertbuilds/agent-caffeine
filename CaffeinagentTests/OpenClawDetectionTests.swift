import XCTest

/// OpenClaw is matched and judged by activity: no state of a turn is read
/// yet (docs/research/12-openclaw.md).
final class OpenClawCatalogTests: XCTestCase {
    typealias Row = ProcessInfoRow
    private let catalog = AgentCatalog.standard
    private let node = "/opt/homebrew/Cellar/node/26.8.1/bin/node"
    private let script = "/opt/homebrew/bin/openclaw"

    func testMatch() {
        let cases: [(name: String, args: [String], role: AgentRole?)] = [
            ("the TUI", ["node", script, "tui"], .session),
            ("one turn from the shell", ["node", script, "agent", "--message", "hi"], .session),
            ("no command", ["node", script], .session),
            ("the process with the title of the CLI", ["openclaw"], .session),
            ("the gateway in the foreground", ["node", script, "gateway", "--port", "18789"], .engine),
            ("the gateway, run", ["node", script, "gateway", "run"], .engine),
            ("the process with the title of the gateway", ["openclaw-gateway"], .engine),
            ("the state of the gateway", ["node", script, "gateway", "status"], .helper),
            ("the gateway service is restarted", ["node", script, "gateway", "restart"], .helper),
            ("the first setup", ["node", script, "onboard"], nil),
            ("the doctor", ["node", script, "doctor", "--fix"], nil),
            ("an update", ["node", script, "update"], nil),
            ("the plugins", ["node", script, "plugins", "list"], nil),
            ("the state", ["node", script, "status", "--all"], nil),
            ("a script of the user", ["node", "/Users/me/code/openclaw.js"], nil),
        ]
        for c in cases {
            let match = catalog.match(.fixture(10, path: node, args: c.args), userNames: [])
            XCTAssertEqual(match?.role, c.role, c.name)
            if c.role != nil { XCTAssertEqual(match?.definition.id, "openclaw", c.name) }
        }
        let definition = catalog.definitions.first { $0.id == AgentCatalog.openClawID }
        XCTAssertEqual(definition?.displayName, "OpenClaw")
        XCTAssertEqual(definition?.level, .activity)
        XCTAssertEqual(definition?.verified, false)
        XCTAssertEqual(definition?.processNames, ["openclaw"], "The name the old list knew, and no other")
    }

    /// The launcher and the process it starts are one agent, and so are
    /// the gateway and the process with its title. A command that the
    /// gateway runs is a child of it.
    func testInstances() {
        let rows: [Row] = [
            .fixture(700, path: node, args: ["node", script, "tui"]),
            .fixture(701, ppid: 700, path: node, args: ["openclaw"]),
            .fixture(900, path: node, args: ["node", script, "gateway", "--port", "18789"]),
            .fixture(901, ppid: 900, path: node, args: ["openclaw-gateway"]),
            .fixture(910, ppid: 901, path: "/bin/zsh", args: ["zsh", "-c", "sleep 400"]),
        ]
        let instances = catalog.instances(in: rows)
        XCTAssertEqual(instances.map(\.rootPID).sorted(), [700, 900])
        XCTAssertEqual(instances.first { $0.rootPID == 700 }?.rows.map(\.pid), [700, 701])
        XCTAssertEqual(instances.first { $0.rootPID == 900 }?.role, .engine)
        XCTAssertEqual(instances.first { $0.rootPID == 900 }?.rows.map(\.pid), [900, 901, 910])
    }
}
