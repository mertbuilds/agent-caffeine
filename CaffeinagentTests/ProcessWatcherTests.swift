import XCTest

final class ProcessWatcherTests: XCTestCase {
    typealias Row = ProcessWatcher.ProcessRow

    /// One line as `ps -o pid=,ppid=,time=,ucomm=,args=` prints it.
    private func psLine(_ pid: Int32, _ ppid: Int32, _ time: String, _ comm: String, _ args: String) -> String {
        let pid = String(repeating: " ", count: max(0, 5 - "\(pid)".count)) + "\(pid)"
        let ppid = String(repeating: " ", count: max(0, 5 - "\(ppid)".count)) + "\(ppid)"
        return "\(pid) \(ppid) \(time) \(comm.padding(toLength: 16, withPad: " ", startingAt: 0)) \(args)"
    }

    private func row(_ pid: Int32, ppid: Int32 = 1, cpu: Double, comm: String = "claude", args: String = "claude") -> Row {
        Row(pid: pid, ppid: ppid, cpuSeconds: cpu, comm: comm, args: args)
    }

    private func snapshot(_ time: TimeInterval, _ rows: [Row]) -> ProcessWatcher.Snapshot {
        ProcessWatcher.Snapshot(rows: rows, time: time, date: Date(timeIntervalSince1970: 1_800_000_000 + time))
    }

    private let allowlist = ["claude", "codex", "gemini"]

    // MARK: parseCPUTime

    func testParseCPUTime() {
        XCTAssertEqual(ProcessWatcher.parseCPUTime("0:00.01")!, 0.01, accuracy: 1e-9)
        XCTAssertEqual(ProcessWatcher.parseCPUTime("842:39.83")!, 842 * 60 + 39.83, accuracy: 1e-9)
        XCTAssertEqual(ProcessWatcher.parseCPUTime("1:02:03")!, 3723, accuracy: 1e-9)
        XCTAssertEqual(ProcessWatcher.parseCPUTime("1-02:03:04.50")!, 86400 + 7384.5, accuracy: 1e-9)
        XCTAssertNil(ProcessWatcher.parseCPUTime("abc"))
        XCTAssertNil(ProcessWatcher.parseCPUTime("1:2:3:4"))
        XCTAssertNil(ProcessWatcher.parseCPUTime("x-1:00"))
        XCTAssertNil(ProcessWatcher.parseCPUTime("-1:00"))
    }

    // MARK: parseProcessList and agentName

    func testParseProcessList() {
        let output = [
            psLine(48211, 48190, "842:39.83", "claude", "claude --resume"),
            psLine(50110, 50002, "0:03.20", "node", "gemini"),
            psLine(612, 1, "12:01.44", "Google Chrome He", "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer"),
            psLine(700, 1, "0:00.01", "claude", ""),
            "not a ps line",
        ].joined(separator: "\n")
        let rows = ProcessWatcher.parseProcessList(output)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0], Row(pid: 48211, ppid: 48190, cpuSeconds: 842 * 60 + 39.83, comm: "claude", args: "claude --resume"))
        XCTAssertEqual(rows[1].comm, "node")
        XCTAssertEqual(rows[1].args, "gemini")
        XCTAssertEqual(rows[2].comm, "Google Chrome He")
        XCTAssertTrue(rows[2].args.hasPrefix("/Applications/Google Chrome.app/"))
        XCTAssertEqual(rows[3].comm, "claude")
        XCTAssertEqual(rows[3].args, "")
    }

    func testAgentName() {
        let allowed = Set(allowlist)
        XCTAssertEqual(ProcessWatcher.agentName(of: row(1, cpu: 0, comm: "claude", args: "claude --resume"), allowed: allowed), "claude")
        // A node CLI that sets its process title.
        XCTAssertEqual(ProcessWatcher.agentName(of: row(2, cpu: 0, comm: "node", args: "gemini"), allowed: allowed), "gemini")
        XCTAssertNil(ProcessWatcher.agentName(of: row(3, cpu: 0, comm: "node", args: "/opt/homebrew/bin/node server.js"), allowed: allowed))
        // The desktop app shares the name but lives in a bundle, which may contain spaces.
        XCTAssertNil(ProcessWatcher.agentName(of: row(4, cpu: 0, comm: "Claude", args: "/Applications/Claude.app/Contents/MacOS/Claude"), allowed: allowed))
        XCTAssertNil(ProcessWatcher.agentName(of: row(5, cpu: 0, comm: "claude", args: "/Users/me/My Apps/Claude.app/Contents/Helpers/claude --stdio"), allowed: allowed))
        // A CLI in a normal path whose argument mentions a bundle still counts.
        XCTAssertEqual(ProcessWatcher.agentName(of: row(6, cpu: 0, comm: "claude", args: "/usr/local/bin/claude /Applications/Foo.app/Contents/x"), allowed: allowed), "claude")
        XCTAssertNil(ProcessWatcher.agentName(of: row(7, cpu: 0, comm: "codex", args: "/Users/me/.vscode/extensions/openai.chatgpt-0.4.1/bin/macos-aarch64/codex app-server --analytics-default-enabled"), allowed: allowed))
        XCTAssertNil(ProcessWatcher.agentName(of: row(8, cpu: 0, comm: "codex", args: "codex exec-server"), allowed: allowed))
        XCTAssertEqual(ProcessWatcher.agentName(of: row(9, cpu: 0, comm: "codex", args: "codex"), allowed: allowed), "codex")
        XCTAssertEqual(ProcessWatcher.agentName(of: row(10, cpu: 0, comm: "claude", args: ""), allowed: allowed), "claude")
        XCTAssertNil(ProcessWatcher.agentName(of: row(11, cpu: 0, comm: "", args: ""), allowed: allowed))
    }

    // MARK: subtreeCPUDelta and evaluate

    func testFirstSightingIsActive() {
        let result = ProcessWatcher.evaluate(current: snapshot(0, [row(100, cpu: 30)]), previous: nil, lastWork: [:], allowlist: allowlist)
        XCTAssertEqual(result.agents.map(\.state), [.active])
        XCTAssertEqual(result.lastWork[100]?.time, 0)
    }

    func testIdleAgentWaitsAfterGracePeriod() {
        var previous: ProcessWatcher.Snapshot?
        var lastWork: [Int32: ProcessWatcher.WorkMark] = [:]
        var states: [TimeInterval: AgentState] = [:]
        // 0.01 CPU seconds per 5 seconds, well under the work threshold.
        for step in 0...30 {
            let t = TimeInterval(step * 5)
            let current = snapshot(t, [row(100, cpu: 30 + Double(step) * 0.01)])
            let result = ProcessWatcher.evaluate(current: current, previous: previous, lastWork: lastWork, allowlist: allowlist)
            states[t] = result.agents.first?.state
            previous = current
            lastWork = result.lastWork
        }
        XCTAssertEqual(states[115], .active)
        XCTAssertEqual(states[120], .waitingForInput)
        XCTAssertEqual(states[150], .waitingForInput)
    }

    func testBusyChildKeepsAgentActive() {
        var previous: ProcessWatcher.Snapshot?
        var lastWork: [Int32: ProcessWatcher.WorkMark] = [:]
        var last: AgentState?
        for step in 0...60 {
            let t = TimeInterval(step * 5)
            // The agent itself is idle; its build child uses a full core.
            let rows = [row(100, cpu: 30), row(200, ppid: 100, cpu: t, comm: "swift-build", args: "swift build")]
            let current = snapshot(t, rows)
            let result = ProcessWatcher.evaluate(current: current, previous: previous, lastWork: lastWork, allowlist: allowlist)
            last = result.agents.first?.state
            previous = current
            lastWork = result.lastWork
        }
        XCTAssertEqual(last, .active)
    }

    func testExitedChildNeverGivesNegativeDelta() {
        let parent = row(100, cpu: 30)
        let previous: [Int32: Row] = [100: parent, 200: row(200, ppid: 100, cpu: 500, comm: "swift-build")]
        let delta = ProcessWatcher.subtreeCPUDelta(of: parent, children: [:], previous: previous)
        XCTAssertEqual(delta, 0)
    }

    func testReusedPidCountsAsNewProcess() {
        let old = snapshot(0, [row(100, cpu: 500, comm: "zsh", args: "-zsh")])
        let current = snapshot(5, [row(100, cpu: 0.2)])
        let delta = ProcessWatcher.subtreeCPUDelta(of: current.rows[0], children: [:], previous: [100: old.rows[0]])
        XCTAssertEqual(delta, 0.2, accuracy: 1e-9)

        let stale = [Int32(100): ProcessWatcher.WorkMark(time: -1000, date: .distantPast)]
        let result = ProcessWatcher.evaluate(current: current, previous: old, lastWork: stale, allowlist: allowlist)
        XCTAssertEqual(result.agents.map(\.state), [.active])
        XCTAssertEqual(result.lastWork[100]?.time, 5)

        // Same name, but the CPU time went down: also a new process.
        let sameName = snapshot(0, [row(100, cpu: 500)])
        let reused = ProcessWatcher.evaluate(current: current, previous: sameName, lastWork: stale, allowlist: allowlist)
        XCTAssertEqual(reused.agents.map(\.state), [.active])
    }

    func testSubSecondRescanIsNotWork() {
        let mark = ProcessWatcher.WorkMark(time: -200, date: .distantPast)
        let previous = snapshot(10, [row(100, cpu: 30)])
        // 0.01 CPU seconds in 0.2 seconds is 5%, above the threshold, but too short to measure.
        let current = snapshot(10.2, [row(100, cpu: 30.01)])
        let result = ProcessWatcher.evaluate(current: current, previous: previous, lastWork: [100: mark], allowlist: allowlist)
        XCTAssertEqual(result.agents.map(\.state), [.waitingForInput])
        XCTAssertEqual(result.lastWork[100], mark)
    }

    func testLongGapWithLittleCPUIsWaiting() {
        // The agent worked right before the Mac slept for an hour.
        let mark = ProcessWatcher.WorkMark(time: 0, date: .distantPast)
        let previous = snapshot(0, [row(100, cpu: 30)])
        let current = snapshot(3600, [row(100, cpu: 32)])
        let result = ProcessWatcher.evaluate(current: current, previous: previous, lastWork: [100: mark], allowlist: allowlist)
        XCTAssertEqual(result.agents.map(\.state), [.waitingForInput])
    }

    func testSameNameMergesToMostActive() {
        let mark = ProcessWatcher.WorkMark(time: -500, date: .distantPast)
        let previous = snapshot(0, [row(100, cpu: 30), row(101, cpu: 30)])
        let current = snapshot(5, [row(100, cpu: 30), row(101, cpu: 31)])
        let result = ProcessWatcher.evaluate(current: current, previous: previous, lastWork: [100: mark, 101: mark], allowlist: allowlist)
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents.first?.state, .active)
        XCTAssertEqual(result.agents.first?.lastActivity, current.date)
    }

    // MARK: allowlist merge

    private var suiteName = ""
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CaffeinagentTests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshInstallUsesDefaults() {
        XCTAssertEqual(ProcessWatcher.loadAllowlist(from: store), ProcessWatcher.defaultAllowlist)
        XCTAssertEqual(ProcessWatcher.loadAllowlist(from: store), ProcessWatcher.defaultAllowlist)
    }

    func testUpgradeMergesNewDefaultsAcrossTwoLaunches() {
        let added = ["cn", "copilot", "droid", "pi"]
        // Saved by a build that did not store known defaults: the user removed
        // aider and added a custom entry.
        let saved = ProcessWatcher.defaultAllowlist.filter { !added.contains($0) && $0 != "aider" } + ["my-agent"]
        store.set(saved, forKey: "ProcessWatcher.allowlist")

        for launch in 1...2 {
            let list = ProcessWatcher.loadAllowlist(from: store)
            XCTAssertFalse(list.contains("aider"), "launch \(launch)")
            XCTAssertTrue(list.contains("my-agent"), "launch \(launch)")
            for name in added {
                XCTAssertTrue(list.contains(name), "\(name) on launch \(launch)")
            }
            XCTAssertEqual(Set(list), Set(saved + added), "launch \(launch)")
        }
    }

    func testRemovedNewDefaultStaysRemoved() {
        store.set(ProcessWatcher.defaultAllowlist.filter { !["cn", "copilot", "droid", "pi"].contains($0) }, forKey: "ProcessWatcher.allowlist")
        var list = ProcessWatcher.loadAllowlist(from: store)
        list.removeAll { $0 == "pi" }
        store.set(list, forKey: "ProcessWatcher.allowlist")
        XCTAssertFalse(ProcessWatcher.loadAllowlist(from: store).contains("pi"))
    }
}
