import XCTest

final class LoginItemTests: XCTestCase {
    func testState() {
        let cases: [(LoginItemStatus, inApplications: Bool, LoginItemState, isOn: Bool)] = [
            (.enabled, true, .on, true),
            (.notRegistered, true, .off, false),
            (.notFound, true, .off, false),
            // Registered, and turned off in Login Items.
            (.requiresApproval, true, .needsApproval, true),
            // A copy outside the Applications folder is never a login item.
            (.enabled, false, .unavailable, false),
            (.notRegistered, false, .unavailable, false),
            (.requiresApproval, false, .unavailable, false),
        ]
        for (status, inApplications, state, isOn) in cases {
            let got = LoginItemState.state(status: status, inApplications: inApplications)
            XCTAssertEqual(got, state, "\(status) \(inApplications)")
            XCTAssertEqual(got.isOn, isOn, "\(status) \(inApplications)")
        }
    }

    /// Checked at the first launch, and later as macOS has it.
    func testTheBoxOfTheSetupWindow() {
        let cases: [(LoginItemState, firstRun: Bool, Bool?)] = [
            (.off, true, true),
            (.off, false, false),
            (.on, true, true),
            (.on, false, true),
            (.needsApproval, false, true),
            (.unavailable, true, nil),
            (.unavailable, false, nil),
        ]
        for (state, firstRun, box) in cases {
            XCTAssertEqual(Onboarding.openAtLoginBox(state, firstRun: firstRun), box, "\(state) \(firstRun)")
        }
    }
}
