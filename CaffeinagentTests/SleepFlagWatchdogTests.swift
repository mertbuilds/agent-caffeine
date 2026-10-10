import XCTest

private final class FakeFlag: SleepFlagAccessing {
    var value = false
    var setFails = false
    var writes: [Bool] = []
    var forced: [Bool] = []
    /// What a later read gives, as when powerd applies a stored setting.
    var valueAfterNextSet: Bool?

    func read() -> Bool? { value }

    func set(_ on: Bool, force: Bool) -> Bool {
        writes.append(on)
        forced.append(force)
        if !setFails { value = on }
        let result = value
        if let later = valueAfterNextSet {
            value = later
            valueAfterNextSet = nil
        }
        return result
    }
}

/// Like the real flag: a write stores the setting, and powerd applies it to
/// the kernel value a moment later.
private final class LateFlag: SleepFlagAccessing {
    var value = false
    var stored = false
    var writes: [Bool] = []
    var forced: [Bool] = []

    func read() -> Bool? { value }

    func set(_ on: Bool, force: Bool) -> Bool {
        if !force, value == on { return on }
        writes.append(on)
        forced.append(force)
        stored = on
        return value
    }

    func powerdApplies() { value = stored }
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
    private let start: TimeInterval = 1_000

    func testHeartbeatKeepsFlag() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        for step in 1...20 {
            let now = start + Double(step) * 15
            XCTAssertEqual(watchdog.tick(now: now), .none)
            watchdog.heartbeat(now: now)
        }
        XCTAssertTrue(watchdog.setByHelper)
    }

    func testLostHeartbeatClearsAfterTimeout() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        watchdog.heartbeat(now: start + 15)
        XCTAssertEqual(watchdog.tick(now: start + 74), .none)
        XCTAssertEqual(watchdog.tick(now: start + 75), .clearFlag)
        // Still due until the caller confirms the clear.
        XCTAssertEqual(watchdog.tick(now: start + 80), .clearFlag)
        watchdog.didClear()
        XCTAssertEqual(watchdog.tick(now: start + 85), .none)
    }

    func testFlagNotSetByHelperIsNeverCleared() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.heartbeat(now: start)
        XCTAssertEqual(watchdog.tick(now: start), .none)
        XCTAssertEqual(watchdog.tick(now: start + 100_000), .none)
    }

    func testRestartWithMarkerClears() {
        let watchdog = SleepFlagWatchdog(markerExists: true)
        XCTAssertEqual(watchdog.tick(now: start), .clearFlag)
    }

    func testReconnectWithinTimeoutKeepsFlag() {
        var watchdog = SleepFlagWatchdog(markerExists: false)
        watchdog.willSet(now: start)
        watchdog.heartbeat(now: start + 59)
        XCTAssertEqual(watchdog.tick(now: start + 100), .none)
    }
}

final class HelperClockTests: XCTestCase {
    func testClockMovesForwardAndIsNotTheDate() {
        let first = HelperCore.awakeSeconds()
        let second = HelperCore.awakeSeconds()
        XCTAssertGreaterThanOrEqual(second, first)
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, Date().timeIntervalSince1970 / 2, "Seconds since boot, not since 1970")
    }
}

final class HelperCoreTests: XCTestCase {
    private var now: TimeInterval = 1_000

    private func makeCore(flag: SleepFlagAccessing, marker: FakeMarker) -> HelperCore {
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
        XCTAssertTrue(marker.exists, "One read is no proof at boot")
        core.tick()
        XCTAssertTrue(marker.exists)
        core.tick()
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
        XCTAssertEqual(flag.forced, [true, false, false])
    }

    func testRestartWritesFalseAlsoWhenTheFlagReadsOff() {
        let flag = FakeFlag(), marker = FakeMarker(exists: true)
        // Boot: the kernel says off, and the stored setting comes on a moment later.
        flag.valueAfterNextSet = true
        let core = makeCore(flag: flag, marker: marker)
        core.tick()
        XCTAssertEqual(flag.writes, [false])
        XCTAssertEqual(flag.forced, [true], "The write happens whatever the read says")
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.exists)
        // The flag came back, so the count of checks starts again.
        core.tick()
        XCTAssertFalse(flag.value)
        core.tick()
        XCTAssertTrue(marker.exists)
        core.tick()
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(flag.value)
    }

    func testClientSetEndsTheRecovery() {
        let flag = FakeFlag(), marker = FakeMarker(exists: true)
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        core.tick()
        XCTAssertTrue(core.setSleepDisabled(true))
        now += 30
        core.tick()
        XCTAssertTrue(flag.value, "A fresh set is under the watchdog, not under the recovery")
        XCTAssertTrue(marker.exists)
        XCTAssertFalse(core.setSleepDisabled(false))
        XCTAssertFalse(marker.exists)
    }

    func testClientClearDuringRecoveryKeepsTheMarkerUntilConfirmed() {
        let flag = FakeFlag(), marker = FakeMarker(exists: true)
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(false))
        XCTAssertEqual(flag.forced, [true])
        XCTAssertTrue(marker.exists)
        core.tick()
        core.tick()
        XCTAssertFalse(marker.exists)
    }

    func testShutdownClearsAFlagTheHelperOwns() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        _ = core.setSleepDisabled(true)
        core.shutdown()
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
    }

    func testShutdownLeavesAForeignFlag() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        _ = core.setSleepDisabled(true)
        core.shutdown()
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testShutdownThatCannotClearKeepsTheMarker() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        _ = core.setSleepDisabled(true)
        flag.setFails = true
        core.shutdown()
        XCTAssertTrue(marker.exists)
        XCTAssertTrue(core.setByHelper)
    }

    func testShutdownDuringRecoveryClearsAndKeepsTheMarker() {
        let flag = FakeFlag(), marker = FakeMarker(exists: true)
        flag.value = true
        let core = makeCore(flag: flag, marker: marker)
        core.shutdown()
        XCTAssertFalse(flag.value)
        XCTAssertTrue(marker.exists, "The next start checks again")
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
        XCTAssertTrue(marker.exists, "Not confirmed is not proof that nothing was written")
        XCTAssertEqual(flag.forced, [false, true], "False is written whatever the kernel reports")
        core.tick()
        core.tick()
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(flag.value)
    }

    /// The set was not confirmed in time, and powerd applies it later. The
    /// old code read "off", wrote nothing and dropped the marker: the flag
    /// came on for ever with nobody to clear it.
    func testSetThatIsAppliedLateIsTakenBack() {
        let flag = LateFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(true))
        XCTAssertEqual(flag.writes, [true, false])
        XCTAssertEqual(flag.forced, [false, true])
        XCTAssertFalse(flag.stored, "What powerd applies later is off")
        XCTAssertTrue(marker.exists)
        XCTAssertTrue(core.setByHelper)
        flag.powerdApplies()
        core.tick()
        XCTAssertTrue(marker.exists)
        core.tick()
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
        XCTAssertFalse(flag.value)
    }

    /// powerd applies the "on" first and the "off" after it.
    func testLateOnIsClearedBeforeTheMarkerGoes() {
        let flag = LateFlag(), marker = FakeMarker()
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(true))
        flag.value = true
        core.tick()
        XCTAssertEqual(flag.writes.last, false)
        XCTAssertTrue(marker.exists)
        flag.powerdApplies()
        XCTAssertFalse(flag.value)
        core.tick()
        core.tick()
        XCTAssertTrue(marker.exists, "The count of checks started again")
        core.tick()
        XCTAssertFalse(marker.exists)
        XCTAssertFalse(core.setByHelper)
    }

    func testANewSetEndsTheRecoveryOfAFailedOne() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.setFails = true
        let core = makeCore(flag: flag, marker: marker)
        XCTAssertFalse(core.setSleepDisabled(true))
        flag.setFails = false
        XCTAssertTrue(core.setSleepDisabled(true))
        now += 30
        core.tick()
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.exists)
    }
}

final class HelperServiceTests: XCTestCase {
    /// A signal that nothing else in the test run uses.
    private let stopSignal = SIGUSR2

    override func tearDown() {
        signal(stopSignal, SIG_DFL)
    }

    private let events = FakeWakeEvents()
    private lazy var alarm = WakeAlarmCore(store: events, date: { 1_800_000_000 }, awake: { 1_000 })

    private func stop(_ service: HelperService, exited: XCTestExpectation) {
        service.exitOnTermination(signal: stopSignal)
        kill(getpid(), stopSignal)
        wait(for: [exited], timeout: 5)
    }

    /// launchd stops the helper: the flag it owns is cleared, then it exits.
    func testTerminationClearsTheFlagAndExits() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = HelperCore(flag: flag, marker: marker, timeout: 60, now: { 1_000 })
        XCTAssertTrue(core.setSleepDisabled(true))
        let exited = expectation(description: "exit")
        var seen: [(code: Int32, flag: Bool, marker: Bool)] = []
        let service = HelperService(core: core, alarm: alarm) { code in
            seen.append((code, flag.value, marker.exists))
            exited.fulfill()
        }
        stop(service, exited: exited)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.code, 0)
        XCTAssertEqual(seen.first?.flag, false, "Cleared before the exit")
        XCTAssertEqual(seen.first?.marker, false)
        XCTAssertEqual(flag.forced.last, true)
    }

    /// After an update the app asks the helper to leave: it clears the flag
    /// it owns, replies, then exits with 0, so launchd does not take the
    /// exit for a crash.
    func testRetireClearsTheFlagRepliesAndExits() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = HelperCore(flag: flag, marker: marker, timeout: 60, now: { 1_000 })
        XCTAssertTrue(core.setSleepDisabled(true))
        let exited = expectation(description: "exit")
        var order: [String] = []
        let service = HelperService(core: core, alarm: alarm) { code in
            order.append("exit \(code), flag \(flag.value), marker \(marker.exists)")
            exited.fulfill()
        }
        service.retire { order.append("reply, flag \(flag.value)") }
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(order, ["reply, flag false", "exit 0, flag false, marker false"])
    }

    func testRetireLeavesAForeignFlagAndExits() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.value = true
        let core = HelperCore(flag: flag, marker: marker, timeout: 60, now: { 1_000 })
        let exited = expectation(description: "exit")
        let service = HelperService(core: core, alarm: alarm) { _ in exited.fulfill() }
        service.retire {}
        wait(for: [exited], timeout: 5)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testTerminationLeavesAForeignFlagAndExits() {
        let flag = FakeFlag(), marker = FakeMarker()
        flag.value = true
        let core = HelperCore(flag: flag, marker: marker, timeout: 60, now: { 1_000 })
        let exited = expectation(description: "exit")
        let service = HelperService(core: core, alarm: alarm) { _ in exited.fulfill() }
        stop(service, exited: exited)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testTerminationThatCannotClearKeepsTheMarkerAndExits() {
        let flag = FakeFlag(), marker = FakeMarker()
        let core = HelperCore(flag: flag, marker: marker, timeout: 60, now: { 1_000 })
        XCTAssertTrue(core.setSleepDisabled(true))
        flag.setFails = true
        let exited = expectation(description: "exit")
        let service = HelperService(core: core, alarm: alarm) { _ in exited.fulfill() }
        stop(service, exited: exited)
        XCTAssertTrue(marker.exists, "The next start tries again")
    }

    private let appleAlarm = WakeEvent(date: Date(timeIntervalSince1970: 1_800_000_500), owner: "com.apple.alarm.user-invisible", type: "wake")

    private func idleService(exited: XCTestExpectation) -> HelperService {
        let core = HelperCore(flag: FakeFlag(), marker: FakeMarker(), timeout: 60, now: { 1_000 })
        return HelperService(core: core, alarm: alarm) { _ in exited.fulfill() }
    }

    func testTheWakeAlarmCallRepliesWithTheTimeAndTheCode() {
        let exited = expectation(description: "exit")
        let service = idleService(exited: exited)
        var replies: [String] = []
        let answered = expectation(description: "answered")
        answered.expectedFulfillmentCount = 4
        for time in [1_800_003_600, 1_800_000_005, 0, Double.nan] {
            service.setWakeAlarm(at: time) { time, code in
                replies.append("\(Int(time)) \(code)")
                answered.fulfill()
            }
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(replies, ["1800003600 0", "0 2", "0 0", "0 1"])
        XCTAssertEqual(events.scheduled, [1_800_003_600])
        stop(service, exited: exited)
    }

    func testTerminationTakesTheWakeAlarmAwayAndExits() {
        events.list = [appleAlarm]
        let exited = expectation(description: "exit")
        let service = idleService(exited: exited)
        let answered = expectation(description: "answered")
        service.setWakeAlarm(at: 1_800_003_600) { _, _ in answered.fulfill() }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(events.oursListed, [1_800_003_600])
        stop(service, exited: exited)
        XCTAssertEqual(events.list, [appleAlarm])
    }

    func testRetireTakesTheWakeAlarmAwayAndExits() {
        events.list = [appleAlarm]
        let exited = expectation(description: "exit")
        let service = idleService(exited: exited)
        let answered = expectation(description: "answered")
        service.setWakeAlarm(at: 1_800_003_600) { _, _ in answered.fulfill() }
        wait(for: [answered], timeout: 5)
        var listedAtReply: [TimeInterval]?
        service.retire { listedAtReply = self.events.oursListed }
        wait(for: [exited], timeout: 5)
        XCTAssertEqual(listedAtReply, [])
        XCTAssertEqual(events.list, [appleAlarm])
    }

    /// A call that was under way when the app retired the helper comes
    /// after its shutdown. An alarm set then would stay behind a helper
    /// that left.
    func testNoWakeAlarmIsSetAfterRetire() {
        let exited = expectation(description: "exit")
        let service = idleService(exited: exited)
        service.retire {}
        wait(for: [exited], timeout: 5)
        var reply: String?
        let answered = expectation(description: "answered")
        service.setWakeAlarm(at: 1_800_003_600) { time, code in
            reply = "\(Int(time)) \(code)"
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(reply, "0 \(WakeAlarmRefusal.notCancelled.rawValue)")
        XCTAssertEqual(events.scheduled, [])
        XCTAssertEqual(events.list, [])
    }

    /// A listener and a client in this process, with no name in launchd.
    private func connect(to service: HelperService) -> (NSXPCListener, NSXPCConnection, SleepFlagHelperProtocol?) {
        let listener = NSXPCListener.anonymous()
        listener.delegate = service
        listener.resume()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepFlagHelperProtocol.self)
        connection.resume()
        return (listener, connection, connection.remoteObjectProxyWithErrorHandler { _ in } as? SleepFlagHelperProtocol)
    }

    /// The app dies with an alarm set: its connection ends, and the
    /// helper takes the alarm away after the grace, here none.
    func testTheWakeAlarmGoesAfterTheConnectionOfTheClientEnded() {
        events.list = [appleAlarm]
        let alarm = WakeAlarmCore(store: events, date: { 1_800_000_000 }, awake: { 1_000 }, clientGrace: 0)
        let core = HelperCore(flag: FakeFlag(), marker: FakeMarker(), timeout: 60, now: { 1_000 })
        let service = HelperService(core: core, alarm: alarm) { _ in }
        let (listener, connection, helper) = connect(to: service)
        defer { listener.invalidate() }
        let answered = expectation(description: "answered")
        var reply: String?
        helper?.setWakeAlarm(at: 1_800_003_600) { time, code in
            reply = "\(Int(time)) \(code)"
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        XCTAssertEqual(reply, "1800003600 0")
        let cancelled = expectation(description: "cancelled")
        events.onCancel = { cancelled.fulfill() }
        connection.invalidate()
        wait(for: [cancelled], timeout: 5)
        // After the call under way on the queue of the service.
        let idle = expectation(description: "idle")
        service.status { _, _, _ in idle.fulfill() }
        wait(for: [idle], timeout: 5)
        XCTAssertEqual(events.cancelled, [1_800_003_600])
        XCTAssertEqual(events.list, [appleAlarm])
    }

    /// The client stays connected: nothing takes the alarm away.
    func testTheWakeAlarmStaysWhileTheClientIsConnected() {
        let alarm = WakeAlarmCore(store: events, date: { 1_800_000_000 }, awake: { 1_000 }, clientGrace: 0)
        let core = HelperCore(flag: FakeFlag(), marker: FakeMarker(), timeout: 60, now: { 1_000 })
        let service = HelperService(core: core, alarm: alarm) { _ in }
        let (listener, connection, helper) = connect(to: service)
        defer {
            connection.invalidate()
            listener.invalidate()
        }
        let answered = expectation(description: "answered")
        helper?.setWakeAlarm(at: 1_800_003_600) { _, _ in answered.fulfill() }
        wait(for: [answered], timeout: 5)
        let later = expectation(description: "later")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { later.fulfill() }
        wait(for: [later], timeout: 5)
        let idle = expectation(description: "idle")
        helper?.status { _, _, _ in idle.fulfill() }
        wait(for: [idle], timeout: 5)
        XCTAssertEqual(events.cancelled, [])
        XCTAssertEqual(events.oursListed, [1_800_003_600])
    }

    func testTheStartTakesAwayAnAlarmOfAnEarlierRun() {
        events.list = [appleAlarm, FakeWakeEvents.ours(1_800_003_600)]
        let exited = expectation(description: "exit")
        let service = idleService(exited: exited)
        service.start()
        XCTAssertEqual(events.list, [appleAlarm])
        stop(service, exited: exited)
    }
}
