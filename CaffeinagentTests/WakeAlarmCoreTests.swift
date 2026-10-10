import XCTest

/// Stands in for the system's list of scheduled power events. Like the real
/// one, it schedules and cancels only with our owner name and the type "wake".
final class FakeWakeEvents: WakeEventStoring {
    var list: [WakeEvent] = []
    var scheduled: [TimeInterval] = []
    var cancelled: [TimeInterval] = []
    var scheduleFails = false
    /// The call says yes and the list does not show the event.
    var dropsSchedules = false
    /// The call adds the event twice.
    var doublesSchedules = false
    var cancelFails = false
    /// One cancel takes every equal entry, not one.
    var cancelTakesAll = false
    /// The list cannot be read.
    var unreadable = false
    /// The list cannot be read from the next schedule on.
    var unreadableAfterSchedule = false
    /// Called at the end of every cancel, on the thread of the caller.
    var onCancel: (() -> Void)?

    func events() -> [WakeEvent]? { unreadable ? nil : list }

    func schedule(at date: Date) -> Bool {
        scheduled.append(date.timeIntervalSince1970)
        if unreadableAfterSchedule { unreadable = true }
        if scheduleFails { return false }
        if dropsSchedules { return true }
        list.append(Self.ours(date.timeIntervalSince1970))
        if doublesSchedules { list.append(Self.ours(date.timeIntervalSince1970)) }
        return true
    }

    func cancel(at date: Date) -> Bool {
        cancelled.append(date.timeIntervalSince1970)
        defer { onCancel?() }
        if cancelFails { return false }
        let event = WakeEvent(date: date, owner: WakeAlarmCore.owner, type: WakeAlarmCore.eventType)
        guard let index = list.firstIndex(of: event) else { return false }
        if cancelTakesAll { list.removeAll { $0 == event } } else { list.remove(at: index) }
        return true
    }

    static func ours(_ time: TimeInterval) -> WakeEvent {
        WakeEvent(date: Date(timeIntervalSince1970: time), owner: WakeAlarmCore.owner, type: WakeAlarmCore.eventType)
    }

    var oursListed: [TimeInterval] {
        list.filter { $0.owner == WakeAlarmCore.owner && $0.type == WakeAlarmCore.eventType }.map(\.date.timeIntervalSince1970)
    }
}

final class WakeAlarmCoreTests: XCTestCase {
    /// Seconds since 1970.
    private var date: TimeInterval = 1_800_000_000
    /// Seconds the Mac was awake.
    private var awake: TimeInterval = 1_000
    private let store = FakeWakeEvents()

    private func makeCore() -> WakeAlarmCore {
        WakeAlarmCore(store: store, date: { self.date }, awake: { self.awake })
    }

    /// Time passes with the Mac awake: both clocks move.
    private func stayAwake(_ seconds: TimeInterval) {
        date += seconds
        awake += seconds
    }

    /// Time passes with the Mac asleep: only the date moves.
    private func sleep(_ seconds: TimeInterval) {
        date += seconds
    }

    private let appleAlarm = WakeEvent(
        date: Date(timeIntervalSince1970: 1_800_000_500),
        owner: "com.apple.alarm.user-invisible-com.apple.acmd.alarm",
        type: "wake"
    )

    // MARK: Range

    func testATimeInRangeIsSetOnce() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        XCTAssertEqual(store.oursListed, [date + 3600])
        XCTAssertEqual(store.scheduled, [date + 3600])
        XCTAssertTrue(core.needsTicks)
    }

    func testTheEdgesOfTheRange() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 19), .refused(.tooSoon))
        XCTAssertEqual(core.set(at: date), .refused(.tooSoon))
        XCTAssertEqual(core.set(at: date - 3600), .refused(.tooSoon))
        XCTAssertEqual(core.set(at: 1), .refused(.tooSoon))
        XCTAssertEqual(core.set(at: date + 8 * 24 * 3600 + 1), .refused(.tooFar))
        XCTAssertEqual(store.scheduled, [])
        XCTAssertFalse(core.needsTicks)
        XCTAssertEqual(core.set(at: date + 20), .set(date + 20))
        XCTAssertEqual(core.set(at: date + 8 * 24 * 3600), .set(date + 8 * 24 * 3600))
    }

    func testWhatIsNoTimeIsRefused() {
        let core = makeCore()
        for value in [Double.nan, .infinity, -.infinity, -1, -date] {
            XCTAssertEqual(core.set(at: value), .refused(.notATime), "\(value)")
        }
        XCTAssertEqual(store.scheduled, [])
        XCTAssertEqual(store.cancelled, [])
    }

    func testTheTimeIsAWholeSecond() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 100.4), .set(date + 100))
        XCTAssertEqual(store.oursListed, [date + 100])
    }

    func testARefusalLeavesTheAlarmThatIsSet() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        XCTAssertEqual(core.set(at: date + 5), .refused(.tooSoon))
        XCTAssertEqual(core.set(at: .nan), .refused(.notATime))
        XCTAssertEqual(store.oursListed, [1_800_003_600])
        XCTAssertEqual(store.cancelled, [])
    }

    // MARK: One alarm

    func testANewTimeTakesThePlaceOfTheOldOne() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        XCTAssertEqual(core.set(at: date + 7200), .set(date + 7200))
        XCTAssertEqual(store.oursListed, [date + 7200])
        XCTAssertEqual(store.cancelled, [date + 3600])
    }

    func testTheSameTimeAgainChangesNothing() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        for _ in 0..<100 {
            XCTAssertEqual(core.set(at: 1_800_003_600), .set(1_800_003_600))
        }
        XCTAssertEqual(store.scheduled, [1_800_003_600])
        XCTAssertEqual(store.cancelled, [])
    }

    func testZeroTakesTheAlarmAway() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        XCTAssertEqual(core.set(at: 0), .cancelled)
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
        XCTAssertEqual(core.set(at: 0), .cancelled, "With no alarm it is done as well")
    }

    func testACancelThatDoesNotWorkIsToldAndTriedAgain() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        store.cancelFails = true
        XCTAssertEqual(core.set(at: 0), .refused(.notCancelled))
        XCTAssertTrue(core.needsTicks)
        store.cancelFails = false
        core.tick()
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }

    func testEqualEntriesOfOursBecomeOne() {
        for takesAll in [false, true] {
            let store = FakeWakeEvents()
            store.cancelTakesAll = takesAll
            let time = date + 3600
            store.list = [FakeWakeEvents.ours(time), appleAlarm, FakeWakeEvents.ours(time), FakeWakeEvents.ours(time)]
            let core = WakeAlarmCore(store: store, date: { self.date }, awake: { self.awake })
            XCTAssertEqual(core.set(at: time), .set(time))
            XCTAssertEqual(store.oursListed, [time])
            XCTAssertTrue(store.list.contains(appleAlarm))
        }
    }

    func testEntriesOfOursAtOtherTimesGo() {
        store.list = [FakeWakeEvents.ours(date + 100), FakeWakeEvents.ours(date + 200), FakeWakeEvents.ours(date + 300)]
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 200), .set(date + 200))
        XCTAssertEqual(store.oursListed, [date + 200])
    }

    // MARK: Entries of others

    func testAnEntryOfSomeoneElseIsNeverTouched() {
        let time = date + 3600
        let foreign = [
            appleAlarm,
            // The same time as ours, from another app.
            WakeEvent(date: Date(timeIntervalSince1970: time), owner: "goguma", type: "wake"),
            WakeEvent(date: Date(timeIntervalSince1970: time), owner: "com.caffeinagent.app", type: "wake"),
            WakeEvent(date: Date(timeIntervalSince1970: time), owner: WakeAlarmCore.owner + ".other", type: "wake"),
            // Our name with a type the helper never makes.
            WakeEvent(date: Date(timeIntervalSince1970: time), owner: WakeAlarmCore.owner, type: "wakepoweron"),
            WakeEvent(date: Date(timeIntervalSince1970: time), owner: WakeAlarmCore.owner, type: "shutdown"),
        ]
        store.list = foreign
        let core = makeCore()
        core.start()
        XCTAssertEqual(core.set(at: time), .set(time))
        XCTAssertEqual(core.set(at: time + 60), .set(time + 60))
        XCTAssertEqual(core.set(at: 0), .cancelled)
        XCTAssertEqual(core.set(at: time), .set(time))
        stayAwake(601)
        core.tick()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        core.shutdown()
        XCTAssertEqual(store.list, foreign)
        XCTAssertEqual(Set(store.cancelled), [time, time + 60, 1_800_000_601 + 3600])
    }

    // MARK: Read-back

    func testAnEventTheListDoesNotShowIsToldAndLeavesNothing() {
        let core = makeCore()
        store.dropsSchedules = true
        XCTAssertEqual(core.set(at: date + 3600), .refused(.notConfirmed))
        XCTAssertFalse(core.needsTicks)
    }

    func testAnEventTheListShowsTwiceIsToldAndTakenAway() {
        let core = makeCore()
        store.doublesSchedules = true
        XCTAssertEqual(core.set(at: date + 3600), .refused(.notConfirmed))
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }

    func testAScheduleThatFailsIsTold() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        store.scheduleFails = true
        XCTAssertEqual(core.set(at: date + 7200), .refused(.notScheduled))
        XCTAssertEqual(store.oursListed, [], "The old alarm went before the new one was asked for")
        XCTAssertFalse(core.needsTicks)
    }

    func testAnOldAlarmThatDoesNotGoStopsTheNewOne() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        store.cancelFails = true
        XCTAssertEqual(core.set(at: date + 7200), .refused(.notCancelled))
        XCTAssertEqual(store.scheduled, [date + 3600], "Never two alarms")
    }

    // MARK: A list that cannot be read

    /// macOS gives an empty list for no events. No list at all means the
    /// read failed, and an alarm of ours can still be there.
    func testAListThatCannotBeReadIsNotAnEmptyList() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        store.unreadable = true
        store.cancelFails = true
        XCTAssertEqual(core.set(at: 0), .refused(.notCancelled), "Not known to be gone")
        XCTAssertEqual(store.cancelled, [date + 3600], "The time it scheduled last is tried all the same")
        XCTAssertTrue(core.needsTicks, "The timer goes on")
        stayAwake(30)
        core.tick()
        XCTAssertTrue(core.needsTicks)
        XCTAssertEqual(store.cancelled, [date - 30 + 3600, date - 30 + 3600])
        XCTAssertEqual(store.oursListed.count, 1, "Still in the list of macOS")
        store.unreadable = false
        store.cancelFails = false
        stayAwake(30)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }

    func testACancelByTheLastTimeIsNotProofWhileTheListCannotBeRead() {
        let core = makeCore()
        _ = core.set(at: date + 3600)
        store.unreadable = true
        XCTAssertEqual(core.set(at: 0), .refused(.notCancelled))
        XCTAssertEqual(store.list, [], "The cancel worked")
        XCTAssertTrue(core.needsTicks, "And nobody could see it")
        store.unreadable = false
        XCTAssertEqual(core.set(at: 0), .cancelled)
        XCTAssertFalse(core.needsTicks)
    }

    func testNoNewTimeWhileTheListCannotBeRead() {
        let core = makeCore()
        store.unreadable = true
        XCTAssertEqual(core.set(at: date + 3600), .refused(.notCancelled))
        XCTAssertEqual(store.scheduled, [])
        XCTAssertTrue(core.needsTicks)
        store.unreadable = false
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
    }

    func testAScheduleThatCannotBeReadBackIsTakenAway() {
        let core = makeCore()
        store.unreadableAfterSchedule = true
        XCTAssertEqual(core.set(at: date + 3600), .refused(.notConfirmed))
        XCTAssertEqual(store.cancelled, [date + 3600])
        XCTAssertEqual(store.list, [])
        XCTAssertTrue(core.needsTicks)
    }

    func testAnAlarmOfAnEarlierRunBehindAListThatCannotBeReadAtTheStart() {
        store.list = [FakeWakeEvents.ours(date + 600), appleAlarm]
        store.unreadable = true
        let core = makeCore()
        core.start()
        XCTAssertTrue(core.needsTicks, "It is looked for again")
        XCTAssertEqual(store.cancelled, [], "No time is known to cancel")
        store.unreadable = false
        stayAwake(30)
        core.tick()
        XCTAssertEqual(store.list, [appleAlarm])
        XCTAssertFalse(core.needsTicks)
    }

    // MARK: Rate limit

    func testThirtyNewTimesPerHour() {
        let core = makeCore()
        let first = date
        for step in 1...30 {
            XCTAssertEqual(core.set(at: first + 3600 + Double(step) * 60), .set(first + 3600 + Double(step) * 60))
            stayAwake(60)
        }
        XCTAssertEqual(core.set(at: first + 9000), .refused(.tooOften))
        XCTAssertEqual(store.oursListed, [first + 3600 + 30 * 60], "The alarm that was set stays")
        // The same time again and a cancel are no new time.
        XCTAssertEqual(core.set(at: first + 3600 + 30 * 60), .set(first + 3600 + 30 * 60))
        // One hour after the first set, one more fits.
        stayAwake(30 * 60)
        XCTAssertEqual(core.set(at: first + 9000), .set(first + 9000))
        XCTAssertEqual(core.set(at: first + 9060), .refused(.tooOften))
        XCTAssertEqual(core.set(at: 0), .cancelled)
        XCTAssertEqual(store.scheduled.count, 31)
    }

    // MARK: Lease

    func testTheAlarmGoesAfterTenMinutesAwakeWithoutTheApp() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 7200), .set(date + 7200))
        stayAwake(599)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1)
        stayAwake(1)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }

    func testTheSameTimeAgainRenewsTheLease() {
        let core = makeCore()
        let time = date + 7200
        XCTAssertEqual(core.set(at: time), .set(time))
        for _ in 0..<5 {
            stayAwake(300)
            core.tick()
            XCTAssertEqual(core.set(at: time), .set(time))
        }
        stayAwake(599)
        core.tick()
        XCTAssertEqual(store.oursListed, [time])
        XCTAssertEqual(store.scheduled, [time])
    }

    func testTimeAsleepDoesNotCountForTheLease() {
        let core = makeCore()
        let time = date + 6 * 3600
        XCTAssertEqual(core.set(at: time), .set(time))
        stayAwake(300)
        sleep(5 * 3600)
        core.tick()
        XCTAssertEqual(store.oursListed, [time], "Five hours of sleep are no time without the app")
        stayAwake(299)
        core.tick()
        XCTAssertEqual(store.oursListed, [time])
        stayAwake(1)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
    }

    func testARefusedTimeDoesNotRenewTheLease() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 620), .set(date + 620))
        stayAwake(605)
        XCTAssertEqual(core.set(at: 1_800_000_620), .refused(.tooSoon))
        core.tick()
        XCTAssertEqual(store.oursListed, [])
    }

    func testATickWithoutALeaseReadsNothing() {
        store.list = [FakeWakeEvents.ours(date + 3600)]
        let core = makeCore()
        core.tick()
        XCTAssertEqual(store.cancelled, [])
    }

    // MARK: Clients

    /// The app died, or quit with no cancel: its connection ended. The
    /// lease would keep the alarm for 10 minutes more.
    func testTheAlarmGoesHalfAMinuteAfterTheLastClientLeft() {
        XCTAssertEqual(WakeAlarmLimits.clientGrace, 30)
        store.list = [appleAlarm]
        let core = makeCore()
        core.clientConnected()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        stayAwake(120)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1, "A client is connected")
        core.clientGone()
        stayAwake(29)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1, "Not yet")
        stayAwake(1)
        core.tick()
        XCTAssertEqual(store.list, [appleAlarm], "30 seconds after the connection ended")
        XCTAssertFalse(core.needsTicks)
    }

    /// The app is started again after an update.
    func testANewConnectionInTimeKeepsTheAlarm() {
        let core = makeCore()
        core.clientConnected()
        _ = core.set(at: date + 3600)
        core.clientGone()
        stayAwake(20)
        core.clientConnected()
        stayAwake(60)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1)
        core.clientGone()
        stayAwake(30)
        core.tick()
        XCTAssertEqual(store.oursListed, [], "Counted again from the end of the new connection")
    }

    func testTheAlarmStaysWhileOneOfTwoClientsIsConnected() {
        let core = makeCore()
        core.clientConnected()
        core.clientConnected()
        _ = core.set(at: date + 3600)
        core.clientGone()
        stayAwake(60)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1)
        core.clientGone()
        core.clientGone()
        stayAwake(30)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
    }

    func testTimeAsleepDoesNotCountAfterTheLastClientLeft() {
        let core = makeCore()
        core.clientConnected()
        _ = core.set(at: date + 3600)
        core.clientGone()
        stayAwake(10)
        sleep(1800)
        core.tick()
        XCTAssertEqual(store.oursListed.count, 1)
        stayAwake(20)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
    }

    func testAnAlarmThatDoesNotGoAfterTheLastClientLeftIsTriedAgain() {
        let core = makeCore()
        core.clientConnected()
        _ = core.set(at: date + 3600)
        core.clientGone()
        store.cancelFails = true
        stayAwake(30)
        core.tick()
        XCTAssertTrue(core.needsTicks)
        store.cancelFails = false
        stayAwake(30)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }

    func testTheLeaseStillEndsAnAlarmOfAClientThatStaysConnected() {
        let core = makeCore()
        core.clientConnected()
        _ = core.set(at: date + 3600)
        stayAwake(WakeAlarmLimits.lease)
        core.tick()
        XCTAssertEqual(store.oursListed, [])
    }

    // MARK: Stop and start

    func testTheAlarmGoesWhenTheHelperStops() {
        let core = makeCore()
        XCTAssertEqual(core.set(at: date + 3600), .set(date + 3600))
        store.list.append(appleAlarm)
        core.shutdown()
        XCTAssertEqual(store.list, [appleAlarm])
    }

    /// The helper keeps nothing in memory across a restart: what is ours is
    /// read from the list.
    func testAnAlarmOfAnEarlierRunGoesAtTheStart() {
        let first = makeCore()
        XCTAssertEqual(first.set(at: date + 3600), .set(date + 3600))
        store.list.append(appleAlarm)
        let second = makeCore()
        second.start()
        XCTAssertEqual(store.list, [appleAlarm])
        XCTAssertFalse(second.needsTicks)
    }

    func testAfterARestartTheSameTimeIsNotScheduledTwice() {
        let first = makeCore()
        let time = date + 3600
        XCTAssertEqual(first.set(at: time), .set(time))
        // A restart without the start step, as the worst case.
        let second = makeCore()
        XCTAssertEqual(second.set(at: time), .set(time))
        XCTAssertEqual(store.scheduled, [time])
        XCTAssertTrue(second.needsTicks)
        XCTAssertEqual(second.set(at: time + 60), .set(time + 60))
        XCTAssertEqual(store.oursListed, [time + 60])
    }

    func testAnAlarmThatDoesNotGoAtTheStartIsTriedAgain() {
        store.list = [FakeWakeEvents.ours(date + 3600)]
        store.cancelFails = true
        let core = makeCore()
        core.start()
        XCTAssertTrue(core.needsTicks)
        store.cancelFails = false
        core.tick()
        XCTAssertEqual(store.oursListed, [])
        XCTAssertFalse(core.needsTicks)
    }
}

final class WakeAlarmResultTests: XCTestCase {
    func testTheReplyGoesThroughTheTwoNumbers() {
        let results: [WakeAlarmResult] = [
            .set(1_800_000_000), .cancelled, .refused(.notATime), .refused(.tooSoon), .refused(.tooFar),
            .refused(.tooOften), .refused(.notScheduled), .refused(.notConfirmed), .refused(.notCancelled),
        ]
        for result in results {
            let reply = result.reply
            XCTAssertEqual(WakeAlarmResult(time: reply.time, code: reply.code), result)
        }
    }

    func testACodeOfALaterBuildIsARefusal() {
        XCTAssertEqual(WakeAlarmResult(time: 1_800_000_000, code: 99), .refused(.unknown))
    }
}

/// Stands in for the XPC connection, with the helper's own rules behind it.
private final class FakeAlarmConnection: SleepFlagHelperConnecting {
    let events = FakeWakeEvents()
    private(set) lazy var core = WakeAlarmCore(store: events, date: { 1_800_000_000 }, awake: { 1_000 })
    var error: Error?
    var asked: [TimeInterval] = []

    func onConnectionLost(_ handler: @escaping () -> Void) {}
    func reconnect() {}
    func setSleepDisabled(_ on: Bool) async throws -> Bool { false }
    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) { (false, false, "1.0 (1)") }
    func heartbeat() async throws -> Bool { false }
    func retire() async throws {}

    func setWakeAlarm(at time: TimeInterval) async throws -> (time: Double, code: Int) {
        asked.append(time)
        if let error { throw error }
        return core.set(at: time).reply
    }
}

final class WakeAlarmClientTests: XCTestCase {
    func testTheClientGivesWhatTheHelperDid() async {
        let helper = FakeAlarmConnection()
        var result = await helper.wakeAlarm(at: 1_800_003_600)
        XCTAssertEqual(result, .set(1_800_003_600))
        result = await helper.wakeAlarm(at: 1_800_000_010)
        XCTAssertEqual(result, .refused(.tooSoon))
        result = await helper.wakeAlarm(at: 1_800_000_000 + 9 * 24 * 3600)
        XCTAssertEqual(result, .refused(.tooFar))
        result = await helper.wakeAlarm(at: 0)
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(helper.asked, [1_800_003_600, 1_800_000_010, 1_800_000_000 + 9 * 24 * 3600, 0])
        XCTAssertEqual(helper.events.oursListed, [])
    }

    func testAReadBackThatFailsReachesTheClient() async {
        let helper = FakeAlarmConnection()
        helper.events.dropsSchedules = true
        let result = await helper.wakeAlarm(at: 1_800_003_600)
        XCTAssertEqual(result, .refused(.notConfirmed))
    }

    /// No answer in time, a helper that went away, a helper of a build that
    /// does not know the call, a helper with another signature.
    func testAHelperThatCannotBeReachedIsAResultAndNoError() async {
        let errors: [Error] = [
            HelperCallError.timedOut, HelperCallError.connectionLost,
            NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid),
            NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionCodeSigningRequirementFailure),
        ]
        for error in errors {
            let helper = FakeAlarmConnection()
            helper.error = error
            let result = await helper.wakeAlarm(at: 1_800_003_600)
            XCTAssertEqual(result, .helperNotAvailable)
            XCTAssertEqual(helper.events.scheduled, [])
        }
    }
}
