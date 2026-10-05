import XCTest

final class OnboardingModelTests: XCTestCase {
    func testSteps() {
        typealias Step = OnboardingStep
        let cases: [(name: String, hooks: [HookStatus], hooksAvailable: Bool, canSetUp: Bool, battery: Bool, helperEnabled: Bool, expected: [Step])] = [
            ("all of it", [.notInstalled], true, true, true, false, [.welcome, .hooks, .lidClosed, .done]),
            ("hooks out of date", [.installed(version: 1), .outdated], true, true, true, false, [.welcome, .hooks, .lidClosed, .done]),
            ("hooks all on", [.installed(version: 1)], true, true, true, false, [.welcome, .lidClosed, .done]),
            ("no agent with hooks", [], true, true, true, false, [.welcome, .lidClosed, .done]),
            ("file cannot be read", [.unreadable], true, true, true, false, [.welcome, .lidClosed, .done]),
            ("not in Applications", [.notInstalled], false, false, true, false, [.welcome, .done]),
            ("no battery", [.notInstalled], true, true, false, false, [.welcome, .hooks, .done]),
            ("helper set up", [.notInstalled], true, true, true, true, [.welcome, .hooks, .done]),
        ]
        for c in cases {
            XCTAssertEqual(
                Onboarding.steps(hookStatuses: c.hooks, hooksAvailable: c.hooksAvailable, canSetUpHelper: c.canSetUp, hasBattery: c.battery, helperEnabled: c.helperEnabled),
                c.expected, c.name
            )
        }
    }
}
