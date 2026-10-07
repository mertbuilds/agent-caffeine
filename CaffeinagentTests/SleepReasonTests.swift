import XCTest

final class SleepReasonTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(_ headline: HoldHeadline, active: Bool = true) -> SleepSnapshot {
        SleepSnapshot(at: at, headline: headline, agentActive: active)
    }

    func testAStopIsTheReasonWhileAnAgentWorkedOrWaited() {
        let cases: [(HoldHeadline, SleepReason?)] = [
            (.safetyStop(.batteryLow(percent: 20)), .battery(percent: 20)),
            (.safetyStop(.tooHot), .tooHot),
            (.paused(until: at.addingTimeInterval(600)), .paused),
            (.notEntitled(.trialOver), .notEntitled(.trialOver)),
            (.notEntitled(.unverified), .notEntitled(.unverified)),
            (.notEntitled(.activationRemoved), .notEntitled(.activationRemoved)),
            (.waitingReleased(.one("Claude Code")), .waitedTooLong(.one("Claude Code"), hold: 300)),
            // The user's own word, and nothing to explain.
            (.switchedOff, nil),
            (.idle(.one("Codex")), nil),
            (.noAgents, nil),
        ]
        for (headline, reason) in cases {
            XCTAssertEqual(SleepReason.reason(snapshot(headline)), reason, "\(headline)")
            XCTAssertNil(SleepReason.reason(snapshot(headline, active: false)), "No agent worked or waited: \(headline)")
        }
    }

    func testTheWaitingHoldOfTheSettingsIsNamed() {
        var waited = snapshot(.waitingReleased(.many(2)))
        waited.waitingHold = 600
        XCTAssertEqual(SleepReason.reason(waited), .waitedTooLong(.many(2), hold: 600))
    }

    /// With a hold the Mac sleeps only when the lid closes on battery
    /// without the helper, or when the user puts it to sleep by hand.
    func testWithAHoldOnlyAClosedLidOnBatteryIsAReason() {
        let held: [HoldHeadline] = [
            .working(.one("Claude Code")), .waitingHeld(.one("Codex")), .finishedRecently(.one("Codex")), .open(.one("Codex")),
            .alwaysOn, .remoteAccess, .reachable(until: at.addingTimeInterval(600)),
        ]
        let cases: [(lid: Bool, battery: Bool, helper: Bool, wanted: Bool, reason: SleepReason?)] = [
            (true, true, false, true, .lidClosedNoHelper),
            (true, true, false, false, .lidClosedNoHelper),
            (true, true, true, false, .lidClosedSettingOff),
            // It should have stayed awake: nothing is known.
            (true, true, true, true, nil),
            // On power a closed lid does not put a held Mac to sleep.
            (true, false, false, true, nil),
            // The user chose Sleep.
            (false, true, false, true, nil),
            (false, false, true, true, nil),
        ]
        for headline in held {
            for c in cases {
                var taken = snapshot(headline)
                (taken.lidClosed, taken.onBattery, taken.helperSetUp, taken.lidClosedWanted) = (c.lid, c.battery, c.helper, c.wanted)
                XCTAssertEqual(SleepReason.reason(taken), c.reason, "\(headline) \(c)")
                taken.agentActive = false
                XCTAssertNil(SleepReason.reason(taken), "\(headline) \(c)")
            }
        }
    }

    func testANoteKeepsTheTimeOfTheSleep() {
        XCTAssertEqual(SleepNote(snapshot(.safetyStop(.tooHot))), SleepNote(at: at, reason: .tooHot))
        XCTAssertNil(SleepNote(snapshot(.switchedOff)))
    }
}
