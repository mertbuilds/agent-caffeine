import XCTest

final class AwakeModeTests: XCTestCase {
    private func agent(_ state: AgentState) -> DetectedAgent {
        DetectedAgent(id: "proc:claude", source: .process, label: "claude", state: state, lastActivity: Date())
    }

    func testShouldHold() {
        let none: [DetectedAgent] = []
        let idle = [agent(.waitingForInput)]
        let working = [agent(.waitingForInput), agent(.active)]
        let expected: [AwakeMode: (none: Bool, idle: Bool, working: Bool)] = [
            .always: (true, true, true),
            .agentOpen: (false, true, true),
            .agentWorking: (false, false, true),
        ]
        for mode in AwakeMode.allCases {
            let want = expected[mode]!
            XCTAssertEqual(mode.shouldHold(enabled: true, agents: none), want.none, "\(mode) with no agents")
            XCTAssertEqual(mode.shouldHold(enabled: true, agents: idle), want.idle, "\(mode) with an idle agent")
            XCTAssertEqual(mode.shouldHold(enabled: true, agents: working), want.working, "\(mode) with a working agent")
            for agents in [none, idle, working] {
                XCTAssertFalse(mode.shouldHold(enabled: false, agents: agents), "\(mode) switched off")
            }
        }
    }
}
