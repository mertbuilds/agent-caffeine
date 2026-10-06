import XCTest

final class ReachableTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func reachable(_ choice: ReachableChoice, at now: Date) -> Reachable {
        var reachable = Reachable()
        reachable.start(choice, now: now)
        return reachable
    }

    // MARK: Start, stop, end

    func testTheChoices() {
        XCTAssertEqual(ReachableChoice.allCases.map(\.length), [3600, 7200, 14400])
        XCTAssertEqual(reachable(.oneHour, at: date(6, 17, 30)).until, date(6, 18, 30))
        XCTAssertEqual(reachable(.twoHours, at: date(6, 17, 30)).until, date(6, 19, 30))
        XCTAssertEqual(reachable(.fourHours, at: date(6, 22)).until, date(7, 2), "Over midnight")
    }

    func testItEndsAtItsTime() {
        var reachable = reachable(.oneHour, at: date(6, 17))
        XCTAssertTrue(reachable.isOn(now: date(6, 17)))
        XCTAssertTrue(reachable.isOn(now: date(6, 17, 59)))
        XCTAssertFalse(reachable.isOn(now: date(6, 18)), "Over at the minute it names")
        reachable.settle(now: date(6, 17, 59))
        XCTAssertEqual(reachable.until, date(6, 18))
        reachable.settle(now: date(6, 18))
        XCTAssertNil(reachable.until)
    }

    func testStopEndsIt() {
        var reachable = reachable(.fourHours, at: date(6, 17))
        reachable.stop()
        XCTAssertEqual(reachable, Reachable())
        XCTAssertFalse(reachable.isOn(now: date(6, 17)))
    }

    func testANewChoiceReplacesTheOldOne() {
        var reachable = reachable(.fourHours, at: date(6, 17))
        reachable.start(.oneHour, now: date(6, 18))
        XCTAssertEqual(reachable.until, date(6, 19))
    }

    /// The Mac slept, or the app did not run: the time counts all the same.
    func testATimeThatEndedWhileTheMacSleptIsOver() {
        var reachable = reachable(.twoHours, at: date(6, 17))
        reachable.settle(now: date(7, 9))
        XCTAssertNil(reachable.until)
    }

    func testRestoreFromTheSavedDate() {
        XCTAssertEqual(Reachable(stored: date(6, 18), now: date(6, 17, 30)).until, date(6, 18))
        XCTAssertNil(Reachable(stored: date(6, 18), now: date(6, 18)).until)
        XCTAssertNil(Reachable(stored: date(6, 18), now: date(9, 12)).until)
        XCTAssertNil(Reachable(stored: nil, now: date(6, 17)).until)
    }

    /// It still ends when the clock shows its time. A clock that went back
    /// by more than the longest choice ends it.
    func testTheClockMovesBack() {
        var reachable = reachable(.fourHours, at: date(6, 17))
        reachable.settle(now: date(6, 17))
        XCTAssertEqual(reachable.until, date(6, 21))
        reachable.settle(now: date(6, 16, 59))
        XCTAssertNil(reachable.until, "More than 4 hours away")
        XCTAssertNil(Reachable(stored: date(6, 21), now: date(5, 21)).until)
        var short = self.reachable(.oneHour, at: date(6, 17))
        short.settle(now: date(6, 15))
        XCTAssertEqual(short.until, date(6, 18), "Within the longest choice the time stands")
    }

    func testTheClockMovesForward() {
        var reachable = reachable(.oneHour, at: date(6, 17))
        reachable.settle(now: date(6, 20))
        XCTAssertNil(reachable.until)
    }

    // MARK: With the pause

    func testAPauseEndsStayReachable() {
        let now = date(6, 17)
        var modes = TimedModes(reachable: reachable(.fourHours, at: now))
        modes.startPause(.oneHour, now: now, calendar: calendar)
        XCTAssertNil(modes.reachable.until)
        XCTAssertEqual(modes.pause.until, date(6, 18))
    }

    func testStayReachableEndsAPause() {
        let now = date(6, 17)
        var modes = TimedModes()
        modes.startPause(.untilTomorrow, now: now, calendar: calendar)
        modes.startReachable(.twoHours, now: now)
        XCTAssertNil(modes.pause.until)
        XCTAssertEqual(modes.reachable.until, date(6, 19))
    }

    func testASafetyStopEndsStayReachableForGood() {
        let now = date(6, 17)
        var modes = TimedModes()
        modes.startReachable(.fourHours, now: now)
        modes.safetyStopped()
        XCTAssertNil(modes.reachable.until)
        modes.settle(now: now.addingTimeInterval(600))
        XCTAssertNil(modes.reachable.until, "It does not come back with the power")
        // A pause is the user's own word and stays.
        modes.startPause(.oneHour, now: now, calendar: calendar)
        modes.safetyStopped()
        XCTAssertEqual(modes.pause.until, date(6, 18))
    }

    /// Only a safety stop ends it, and with the battery floor off the
    /// battery gives none.
    func testWithTheFloorOffTheBatteryDoesNotEndStayReachable() {
        var monitor = SafetyMonitor()
        monitor.batteryFloorEnabled = false
        var modes = TimedModes()
        modes.startReachable(.fourHours, now: date(6, 17))
        func sample(_ percent: Int, _ thermal: ProcessInfo.ThermalState) {
            if monitor.update(SafetyInputs(batteryPercent: percent, onBattery: true, thermalState: thermal)) != nil { modes.safetyStopped() }
        }
        for percent in [20, 10, 5, 1] { sample(percent, .nominal) }
        XCTAssertEqual(modes.reachable.until, date(6, 21))
        sample(40, .serious)
        XCTAssertNil(modes.reachable.until, "Heat still ends it")
    }

    func testTheSwitchEndsBoth() {
        let now = date(6, 17)
        var modes = TimedModes()
        modes.startReachable(.oneHour, now: now)
        modes.switchedOff()
        XCTAssertEqual(modes, TimedModes())
        modes.startPause(.oneHour, now: now, calendar: calendar)
        modes.switchedOff()
        XCTAssertEqual(modes, TimedModes())
    }

    func testSettleEndsEachAtItsOwnTime() {
        let now = date(6, 17)
        var modes = TimedModes()
        modes.startReachable(.oneHour, now: now)
        modes.settle(now: date(6, 17, 59))
        XCTAssertEqual(modes.reachable.until, date(6, 18))
        modes.settle(now: date(6, 18))
        XCTAssertEqual(modes, TimedModes())
    }

    func testTheCostIsOneNumberInOnePlace() {
        XCTAssertEqual(Reachable.batteryPercentPerHour, 1)
        XCTAssertEqual(PanelText.reachableCost, "Uses about 1% of battery per hour")
    }
}
