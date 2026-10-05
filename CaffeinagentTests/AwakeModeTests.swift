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
        for entitlement in [Entitlement.licensed, .trial(daysLeft: 7), .trial(daysLeft: 1)] {
            for mode in AwakeMode.allCases {
                let want = expected[mode]!
                XCTAssertEqual(mode.shouldHold(enabled: true, agents: none, entitlement: entitlement), want.none, "\(mode) \(entitlement) with no agents")
                XCTAssertEqual(mode.shouldHold(enabled: true, agents: idle, entitlement: entitlement), want.idle, "\(mode) \(entitlement) with an idle agent")
                XCTAssertEqual(mode.shouldHold(enabled: true, agents: working, entitlement: entitlement), want.working, "\(mode) \(entitlement) with a working agent")
                for agents in [none, idle, working] {
                    XCTAssertFalse(mode.shouldHold(enabled: false, agents: agents, entitlement: entitlement), "\(mode) \(entitlement) switched off")
                }
            }
        }
    }

    func testExpiredNeverHolds() {
        let lists = [[], [agent(.waitingForInput)], [agent(.active)]]
        for mode in AwakeMode.allCases {
            for agents in lists {
                for enabled in [true, false] {
                    for reason in [ExpiredReason.trialOver, .unverified, .activationRemoved] {
                        XCTAssertFalse(mode.shouldHold(enabled: enabled, agents: agents, entitlement: .expired(reason)), "\(mode) expired \(reason)")
                    }
                }
            }
        }
    }
}
