import XCTest

private final class FakeFlag: SleepFlagAccessing {
    var value = false
    var setFails = false
    var writes: [Bool] = []

    func read() -> Bool? { value }

    func set(_ on: Bool) -> Bool {
        writes.append(on)
        if !setFails { value = on }
        return value
    }
}

private final class FakeMarker: MarkerStoring {
    var exists: Bool
    var writeFails = false

    init(exists: Bool = false) { self.exists = exists }

    func write() -> Bool {
        if writeFails { return false }
        exists = true
        return true
    }

    func remove() { exists = false }
}

final class SleepFlagWatchdogTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testHeartbeatKeepsFlag() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        for step in 1...20 {
            let now = start.addingTimeInterval(Double(step) * 15)
            XCTAssertEqual(watchdog.tick(now: now), .none)
            watchdog.heartbeat(now: now)
        }
        XCTAssertTrue(watchdog.setByHelper)
    }

    func testLostHeartbeatClearsAfterTimeout() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        watchdog.heartbeat(now: start.addingTimeInterval(15))
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(74)), .none)
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(75)), .clearFlag)
        // Still due until the caller confirms the clear.
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(80)), .clearFlag)
        watchdog.didClear()
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(85)), .none)
    }

    func testFlagNotSetByHelperIsNeverCleared() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.heartbeat(now: start)
        XCTAssertEqual(watchdog.tick(now: start), .none)
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(100_000)), .none)
    }

    func testRestartWithMarkerClears() {
        let watchdog = SleepFlagWatchdog(markerExists: true)
        XCTAssertEqual(watchdog.tick(now: start), .clearFlag)
    }

    func testReconnectWithinTimeoutKeepsFlag() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        watchdog.heartbeat(now: start.addingTimeInterval(59))
        XCTAssertEqual(watchdog.tick(now: start.addingTimeInterval(100)), .none)
    }
}

final class HelperCoreTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeCore(flag: FakeFlag, marker: FakeMarker) -> HelperCore {
        HelperCore(flag: flag, marker: marker, timeout: 60, now: { self.now })
    }

    func testSetWritesMarkerAndClearRemovesIt() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertTrue(core.setSleepDisabled(true))
        XCTAssertTrue(marker.exists)
        XCTAssertTrue(core.setByHelper)
        XCTAssertFalse(core.setSleepDisabled(false))
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(flag.value)
    }

    func testWatchdogClearsWhenHeartbeatsStop() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        _ = core.setSleepDisabled(true)
        now += 30
        XCTAssertTrue(core.heartbeat())
        now += 59
        core.tick()
        XCTAssertTrue(flag.value)
        now += 1
        core.tick()
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.heartbeat())
    }

    func testForeignFlagIsNeverCleared() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertTrue(core.setSleepDisabled(true))
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(marker.exists)
        now += 100_000
        core.tick()
        XCTAssertTrue(core.setSleepDisabled(false))
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testRestartWithMarkerClears() {
        let flag = FakeFlag(), marker = FakeMarker(exists: true)
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertTrue(core.setByHelper)
        core.tick()
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
    }

    func testFailedClearKeepsMarkerAndRetries() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        _ = core.setSleepDisabled(true)
        flag.setFails = true
        XCTAssertTrue(core.setSleepDisabled(false))
        XCTAssertTrue(marker.exists)
        XCTAssertTrue(core.setByHelper)
        flag.setFails = false
        now += 60
        core.tick()
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.exists)
    }

    func testNoMarkerNoSet() {
        let flag = FakeFlag(), marker = FakeMarker()
        marker.writeFails = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(true))
        XCTAssertFalse(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testFailedSetLeavesNothingBehind() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.setFails = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(true))
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(marker.exists)
    }
}
