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

    func testNotificationText() {
        XCTAssertEqual(SafetyStop.batteryLow(percent: 20).notificationText, "agent caffeine let your Mac sleep because the battery is at 20 percent")
        XCTAssertEqual(SafetyStop.tooHot.notificationText, "agent caffeine let your Mac sleep because it got too hot")
    }
}
