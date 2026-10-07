import XCTest

final class SafetyMonitorTests: XCTestCase {
    func testEvaluate() {
        let cases: [(percent: Int?, onBattery: Bool, thermal: ProcessInfo.ThermalState, stopped: Bool, want: SafetyStop?)] = [
            (80, true, .nominal, false, nil),
            (21, true, .fair, false, nil),
            (20, true, .nominal, false, .batteryLow(percent: 20)),
            (5, true, .nominal, false, .batteryLow(percent: 5)),
            (5, false, .nominal, false, nil),
            (nil, false, .nominal, false, nil),
            (nil, true, .nominal, false, nil),
            (80, false, .serious, false, .tooHot),
            (80, true, .critical, false, .tooHot),
            (nil, false, .serious, false, .tooHot),
            (10, true, .serious, false, .tooHot),
            (22, true, .nominal, true, .batteryLow(percent: 22)),
            (24, true, .nominal, true, .batteryLow(percent: 24)),
            (25, true, .nominal, true, nil),
            (22, false, .nominal, true, nil),
        ]
        for c in cases {
            let inputs = SafetyInputs(batteryPercent: c.percent, onBattery: c.onBattery, thermalState: c.thermal)
            let got = SafetyMonitor.evaluate(inputs, floor: 20, batteryStopped: c.stopped)
            XCTAssertEqual(got.stop, c.want, "\(c)")
        }
    }

    func testBatteryStopDoesNotFlap() {
        var monitor = SafetyMonitor()
        func update(_ percent: Int, onBattery: Bool = true) -> SafetyStop? {
            monitor.update(SafetyInputs(batteryPercent: percent, onBattery: onBattery, thermalState: .nominal))
        }
        XCTAssertNil(update(21))
        XCTAssertEqual(update(20), .batteryLow(percent: 20))
        XCTAssertEqual(update(21), .batteryLow(percent: 21))
        XCTAssertEqual(update(24), .batteryLow(percent: 24))
        XCTAssertNil(update(25))
        XCTAssertNil(update(21))
        XCTAssertEqual(update(19), .batteryLow(percent: 19))
        XCTAssertNil(update(19, onBattery: false))
        XCTAssertEqual(update(19), .batteryLow(percent: 19))
    }

    func testBatteryStopSurvivesHeat() {
        var monitor = SafetyMonitor()
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 20, onBattery: true, thermalState: .nominal)), .batteryLow(percent: 20))
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 22, onBattery: true, thermalState: .serious)), .tooHot)
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 22, onBattery: true, thermalState: .fair)), .batteryLow(percent: 22))
    }

    func testFloorIsAdjustable() {
        var monitor = SafetyMonitor()
        monitor.batteryFloorPercent = 40
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 40, onBattery: true, thermalState: .nominal)), .batteryLow(percent: 40))
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 44, onBattery: true, thermalState: .nominal)), .batteryLow(percent: 44))
        XCTAssertNil(monitor.update(SafetyInputs(batteryPercent: 45, onBattery: true, thermalState: .nominal)))
    }

    func testStopIsAnnouncedOncePerStop() {
        let low = SafetyStop.batteryLow(percent: 20)
        XCTAssertEqual(SafetyStop.toAnnounce(previous: nil, current: low, wasHolding: true), low)
        // The same stop goes on: a lower level, then heat on top of it.
        XCTAssertNil(SafetyStop.toAnnounce(previous: low, current: .batteryLow(percent: 19), wasHolding: false))
        XCTAssertNil(SafetyStop.toAnnounce(previous: .batteryLow(percent: 19), current: .tooHot, wasHolding: false))
        XCTAssertNil(SafetyStop.toAnnounce(previous: .tooHot, current: nil, wasHolding: false))
        // It ended, so the next one is a new stop.
        XCTAssertEqual(SafetyStop.toAnnounce(previous: nil, current: .tooHot, wasHolding: true), .tooHot)
    }

    func testStopThatEndedNoHoldIsNotAnnounced() {
        XCTAssertNil(SafetyStop.toAnnounce(previous: nil, current: .tooHot, wasHolding: false))
        XCTAssertNil(SafetyStop.toAnnounce(previous: nil, current: nil, wasHolding: true))
    }

    func testWithTheFloorOffTheBatteryNeverStops() {
        var monitor = SafetyMonitor()
        monitor.batteryFloorEnabled = false
        for percent in [20, 5, 1, 0] {
            XCTAssertNil(monitor.update(SafetyInputs(batteryPercent: percent, onBattery: true, thermalState: .nominal)), "\(percent)")
        }
        // Heat has no switch.
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 1, onBattery: true, thermalState: .serious)), .tooHot)
        XCTAssertEqual(monitor.update(SafetyInputs(batteryPercent: 80, onBattery: false, thermalState: .critical)), .tooHot)
        XCTAssertNil(monitor.update(SafetyInputs(batteryPercent: 1, onBattery: true, thermalState: .fair)))
        XCTAssertNil(SafetyMonitor.evaluate(SafetyInputs(batteryPercent: 1, onBattery: true, thermalState: .nominal), floor: nil, batteryStopped: true).stop)
    }

    func testSwitchingTheFloorOffEndsABatteryStop() {
        var monitor = SafetyMonitor()
        let low = SafetyInputs(batteryPercent: 18, onBattery: true, thermalState: .nominal)
        XCTAssertEqual(monitor.update(low), .batteryLow(percent: 18))
        monitor.batteryFloorEnabled = false
        XCTAssertNil(monitor.update(low))
        // Back on, the floor counts from new.
        monitor.batteryFloorEnabled = true
        XCTAssertNil(monitor.update(SafetyInputs(batteryPercent: 22, onBattery: true, thermalState: .nominal)))
        XCTAssertEqual(monitor.update(low), .batteryLow(percent: 18))
    }

    // MARK: No battery limit

    private func warn(_ warning: inout NoLimitBatteryWarning, _ percent: Int?, onBattery: Bool = true, floorEnabled: Bool = false, holding: Bool = true) -> Int? {
        warning.update(SafetyInputs(batteryPercent: percent, onBattery: onBattery, thermalState: .nominal), floorEnabled: floorEnabled, holding: holding)
    }

    func testEachLevelIsToldOnce() {
        var warning = NoLimitBatteryWarning()
        let told = [58, 11, 10, 10, 9, 6, 5, 5, 4, 1].map { warn(&warning, $0) }
        XCTAssertEqual(told, [nil, nil, 10, nil, nil, nil, 5, nil, nil, nil])
    }

    func testALevelThatWasPassedIsNotToldLater() {
        var warning = NoLimitBatteryWarning()
        // The hold began low: the level above is not told after it.
        XCTAssertEqual(warn(&warning, 4), 4)
        XCTAssertNil(warn(&warning, 8))
        XCTAssertNil(warn(&warning, 10))
        // A sample that skips a level tells the real number.
        var skipped = NoLimitBatteryWarning()
        XCTAssertEqual(warn(&skipped, 9), 9)
        XCTAssertEqual(warn(&skipped, 3), 3)
    }

    func testToldAgainAfterChargingOrAbove15Percent() {
        var warning = NoLimitBatteryWarning()
        XCTAssertEqual(warn(&warning, 10), 10)
        XCTAssertNil(warn(&warning, 15), "15 percent is not above 15")
        XCTAssertNil(warn(&warning, 10))
        XCTAssertNil(warn(&warning, 16))
        XCTAssertEqual(warn(&warning, 10), 10)
        XCTAssertEqual(warn(&warning, 5), 5)
        XCTAssertNil(warn(&warning, 5, onBattery: false), "Charging")
        XCTAssertEqual(warn(&warning, 5), 5)
    }

    func testOnlyWhileHoldingOnBatteryWithTheFloorOff() {
        var warning = NoLimitBatteryWarning()
        XCTAssertNil(warn(&warning, 10, holding: false))
        XCTAssertEqual(warn(&warning, 9), 9, "Told when the hold begins")
        var withFloor = NoLimitBatteryWarning()
        XCTAssertNil(warn(&withFloor, 5, floorEnabled: true))
        var onPower = NoLimitBatteryWarning()
        XCTAssertNil(warn(&onPower, 5, onBattery: false))
        var noBattery = NoLimitBatteryWarning()
        XCTAssertNil(warn(&noBattery, nil))
    }

    func testTexts() {
        XCTAssertEqual(
            NoLimitBatteryWarning.notificationText(percent: 10),
            "The battery is at 10%. agent caffeine keeps your Mac awake because the battery limit is off."
        )
        XCTAssertEqual(
            NoLimitBatteryWarning.notificationText(percent: 5),
            "The battery is at 5%. agent caffeine keeps your Mac awake because the battery limit is off."
        )
        var settings = DetectionSettings()
        settings.batteryFloorPercent = 35
        XCTAssertEqual(SafetyText.stillSleeps(settings), "Your Mac still sleeps when the battery is at 35% and when it gets too hot.")
        settings.batteryFloorEnabled = false
        XCTAssertEqual(SafetyText.stillSleeps(settings), "Your Mac still sleeps when it gets too hot. The battery limit is off.")
        XCTAssertTrue(SafetyText.alwaysTold(batteryFloorEnabled: true).contains("because the battery is low or your Mac got too hot"))
        XCTAssertFalse(SafetyText.alwaysTold(batteryFloorEnabled: false).contains("battery is low"))
        for text in [SafetyText.floorOnHelp, SafetyText.floorOffWarning, SafetyText.floorOffQuestion, SafetyText.floorOffConsequence,
                     SafetyText.alwaysTold(batteryFloorEnabled: true), SafetyText.alwaysTold(batteryFloorEnabled: false)] {
            XCTAssertFalse(text.contains("percent") || text.contains("\u{2014}"), text)
        }
    }

    func testNotificationText() {
        XCTAssertEqual(SafetyStop.batteryLow(percent: 20).notificationText, "agent caffeine let your Mac sleep because the battery is at 20%")
        XCTAssertEqual(SafetyStop.tooHot.notificationText, "agent caffeine let your Mac sleep because it got too hot")
    }
}
