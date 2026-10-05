import XCTest

final class MenuModelTests: XCTestCase {
    private func hold(_ id: String, _ name: String, pid: Int32, _ state: WorkState, _ reason: VerdictReason) -> AgentHold {
        AgentHold(
            reading: AgentReading(
                agentID: id, displayName: name, level: .state, identity: ProcessIdentity(pid: pid, startTime: 5),
                verdict: AgentVerdict(state: state, confidence: .reported, reason: reason)
            ),
            cause: nil
        )
    }

    private func claude(pid: Int32, _ state: WorkState, _ reason: VerdictReason = .atPrompt) -> AgentHold {
        hold("claude", "Claude Code", pid: pid, state, reason)
    }

    func testNoAgentsGiveNoRows() {
        XCTAssertEqual(MenuModel.rows(for: []), [])
    }

    func testManyIdleSessionsShareOneLine() {
        let idle = (1...9).map { claude(pid: $0, .idle) }
        let rows = MenuModel.rows(for: idle + [hold("codex", "Codex", pid: 20, .idle, .atPrompt)])
        XCTAssertEqual(rows, [
            MenuAgentRow(id: "idle:claude", title: "Claude Code", state: .idle, detail: "9 idle sessions"),
            MenuAgentRow(id: "idle:codex", title: "Codex", state: .idle, detail: "Idle · Ready for your next message"),
        ])
    }

    func testWorkingAndWaitingSessionsKeepTheirOwnLines() {
        let perAgent = [
            claude(pid: 1, .idle),
            claude(pid: 2, .waitingForUser, .asksPermission),
            claude(pid: 3, .working, .runningCommand(2)),
            claude(pid: 4, .idle),
            claude(pid: 5, .working, .reportsBusy),
        ]
        let labels = [ProcessIdentity(pid: 3, startTime: 5): "website", ProcessIdentity(pid: 2, startTime: 5): "wiki"]
        let rows = MenuModel.rows(for: perAgent, labels: labels)
        XCTAssertEqual(rows.map(\.title), ["Claude Code · website", "Claude Code", "Claude Code · wiki", "Claude Code"])
        XCTAssertEqual(rows.map(\.state), [.working, .working, .waiting, .idle])
        XCTAssertEqual(rows.map(\.detail), [
            "Working · Running 2 commands", "Working · Working on a task", "Waits for you · Waits for your answer", "2 idle sessions",
        ])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testAgentsWithTheSameNameStayApart() {
        let rows = MenuModel.rows(for: [
            hold("codex", "Codex", pid: 1, .idle, .atPrompt),
            hold("codex-desktop", "Codex", pid: 2, .idle, .atPrompt),
            hold("codex", "Codex", pid: 3, .idle, .atPrompt),
        ])
        XCTAssertEqual(rows.map(\.detail), ["2 idle sessions", "Idle · Ready for your next message"])
    }

    func testSessionLabelIsTheFolderName() {
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website"), "website")
        XCTAssertEqual(MenuModel.sessionLabel(workingDirectory: "/Users/me/code/website/"), "website")
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: "/"))
        XCTAssertNil(MenuModel.sessionLabel(workingDirectory: nil))
    }

    func testLidClosedStatus() {
        XCTAssertEqual(MenuModel.lidClosedStatus(helper: .enabled, wanted: true), .on)
        XCTAssertEqual(MenuModel.lidClosedStatus(helper: .enabled, wanted: false), .off)
        for helper in [HelperStatus.notRegistered, .requiresApproval, .notFound] {
            XCTAssertEqual(MenuModel.lidClosedStatus(helper: helper, wanted: true), .notSetUp)
            XCTAssertEqual(MenuModel.lidClosedStatus(helper: helper, wanted: false), .notSetUp)
        }
        XCTAssertEqual(LidClosedStatus.notSetUp.text, "Lid closed on battery: not set up")
    }
}
