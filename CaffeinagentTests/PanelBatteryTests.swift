import XCTest

final class PanelBatteryTests: XCTestCase {
    private func input(_ headline: HoldHeadline = .working(.one("Claude Code")), percent: Int? = 58, onBattery: Bool = true) -> PanelInput {
        var input = PanelInput(decision: HoldDecision(hold: headline.keepsAwake, lidClosedFlag: false, headline: headline, perAgent: []))
        input.onBattery = onBattery
        input.batteryPercent = percent
        return input
    }

    func testShownOnlyOnBatteryWhileAgentCaffeineCouldHold() {
        XCTAssertNotNil(MenuModel.battery(input()))
        XCTAssertNotNil(MenuModel.battery(input(.noAgents)), "Also while no agent works")
        XCTAssertNil(MenuModel.battery(input(onBattery: false)), "Wall power")
        XCTAssertNil(MenuModel.battery(input(percent: nil)), "A Mac without a battery")
        var off = input(.switchedOff)
        off.enabled = false
        XCTAssertNil(MenuModel.battery(off))
        var paused = input(.paused(until: Date(timeIntervalSince1970: 2_000_000)))
        paused.pausedUntil = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertNil(MenuModel.battery(paused))
        var expired = input(.notEntitled(.trialOver))
        expired.entitlement = .expired(.trialOver)
        XCTAssertNil(MenuModel.battery(expired))
        var trial = input()
        trial.entitlement = .trial(daysLeft: 3)
        XCTAssertNotNil(MenuModel.battery(trial))
        // The state of the menu carries it.
        XCTAssertEqual(MenuModel.state(input(), now: Date()).battery, MenuModel.battery(input()))
        XCTAssertNil(MenuModel.state(input(onBattery: false), now: Date()).battery)
    }

    func testFillTickAndStrings() throws {
        var input = input()
        input.settings.batteryFloorPercent = 20
        let battery = try XCTUnwrap(MenuModel.battery(input))
        XCTAssertEqual(battery.fill, 0.58, accuracy: 0.0001)
        XCTAssertEqual(battery.tick, 0.2, accuracy: 0.0001)
        XCTAssertEqual(battery.level, .normal)
        XCTAssertEqual(battery.leading, "58 percent battery")
        XCTAssertEqual(battery.trailing, "Sleeps below 20 percent")
        XCTAssertEqual(battery.accessibilityLabel, "Battery 58 percent, agent caffeine lets your Mac sleep below 20 percent")
    }

    func testTheRealFloorIsUsed() throws {
        var input = input()
        input.settings.batteryFloorPercent = 35
        let battery = try XCTUnwrap(MenuModel.battery(input))
        XCTAssertEqual(battery.tick, 0.35, accuracy: 0.0001)
        XCTAssertEqual(battery.trailing, "Sleeps below 35 percent")
    }

    func testAmberWithinTenPointsOfTheFloor() {
        var input = input()
        input.settings.batteryFloorPercent = 20
        let levels = [31, 30, 25, 21].map { percent -> PanelBattery.Level? in
            input.batteryPercent = percent
            return MenuModel.battery(input)?.level
        }
        XCTAssertEqual(levels, [.normal, .nearFloor, .nearFloor, .nearFloor])
    }

    func testRedWhileTheFloorStoppedAgentCaffeine() throws {
        var input = input(.safetyStop(.batteryLow(percent: 19)), percent: 19)
        input.settings.batteryFloorPercent = 20
        let battery = try XCTUnwrap(MenuModel.battery(input))
        XCTAssertEqual(battery.level, .stopped)
        XCTAssertEqual(battery.trailing, "Starts again at 25 percent")
        XCTAssertEqual(battery.accessibilityLabel, "Battery 19 percent, agent caffeine starts again at 25 percent")
        // Heat is not the battery's stop.
        let hot = self.input(.safetyStop(.tooHot), percent: 60)
        XCTAssertEqual(MenuModel.battery(hot)?.level, .normal)
    }

    func testAPercentOutOfRangeIsCut() {
        XCTAssertEqual(MenuModel.battery(input(percent: 104))?.fill, 1)
        XCTAssertEqual(MenuModel.battery(input(percent: -3))?.fill, 0)
    }

    func testNoLineEndsWithAPeriodOrAbbreviates() throws {
        for input in [input(), input(.safetyStop(.batteryLow(percent: 19)), percent: 19)] {
            let battery = try XCTUnwrap(MenuModel.battery(input))
            for text in [battery.leading, battery.trailing, battery.accessibilityLabel] {
                XCTAssertFalse(text.hasSuffix("."), text)
                XCTAssertFalse(text.contains("%"), text)
            }
        }
    }
}
