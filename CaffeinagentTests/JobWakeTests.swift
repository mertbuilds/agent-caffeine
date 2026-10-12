import XCTest

/// The rules of the loop of "Wake for jobs", with the times passed in.
final class JobWakeTests: XCTestCase {
    private let clock = JobTime.clock()
    /// A Saturday.
    private let noon = JobTime.date("2026-10-10 12:00")
    private var wake = JobWake()
    /// Seconds the Mac was awake and asleep, as the two clocks give them.
    private var awake: TimeInterval = 1000
    private var asleep: TimeInterval = 0

    override func setUp() {
        wake = JobWake()
        awake = 1000
        asleep = 0
    }

    private func at(_ text: String) -> Date { JobTime.date(text) }
    private func seconds(_ text: String) -> TimeInterval { at(text).timeIntervalSince1970 }

    private func job(_ name: String, _ cron: String) -> ScheduledJob {
        ScheduledJob(id: "crontab:\(name)", source: .crontab, name: name, schedule: .cron(JobTime.cron(cron)))
    }

    /// The feature on, and the job "backup" at 21:00 switched on.
    private func input(_ jobs: [ScheduledJob]? = nil, on: [String] = ["backup"]) -> JobWakeInput {
        var input = JobWakeInput(readings: [JobSourceReading(source: .crontab, jobs: jobs ?? [job("backup", "0 21 * * *")])])
        input.settings.wakeForJobs = true
        for name in on { input.settings.set(true, for: "crontab:\(name)") }
        return input
    }

    @discardableResult
    private func turn(_ input: JobWakeInput, _ now: Date, willSleep: Bool = false) -> TimeInterval? {
        wake.turn(input, now: now, awake: awake, asleep: asleep, clock: clock, willSleep: willSleep)
    }

    /// A turn, and the helper sets what was asked for.
    private func set(_ input: JobWakeInput, _ now: Date, willSleep: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        guard let time = turn(input, now, willSleep: willSleep), time > 0 else { return XCTFail("No time was asked for", file: file, line: line) }
        wake.answered(.set(time), for: time, now: now, awake: awake)
    }

    /// The Mac sleeps until `date`.
    private func sleep(for seconds: TimeInterval) {
        asleep += seconds
    }

    private var kinds: [JobEvent.Kind] { wake.memory.history.events.map(\.kind) }

    // MARK: The alarm

    func testThePlanGoesToTheHelperAndItsAnswerIsTheAlarm() {
        let time = turn(input(), noon)
        XCTAssertEqual(time, seconds("2026-10-10 20:59"), "One minute before the job")
        XCTAssertEqual(wake.status, .asking)
        XCTAssertNil(wake.alarm)
        XCTAssertNil(turn(input(), noon), "No second call while the first is under way")
        wake.answered(.set(time!), for: time!, now: noon, awake: awake)
        let alarm = JobAlarm(at: at("2026-10-10 20:59"), fireAt: at("2026-10-10 21:00"), jobID: "crontab:backup", jobName: "backup")
        XCTAssertEqual(wake.alarm, alarm)
        XCTAssertEqual(wake.status, .alarmSet(alarm))
        XCTAssertEqual(wake.memory.owedAlarm, time)
        XCTAssertEqual(kinds, [.alarmSet])
        XCTAssertEqual(wake.nextTurn, at("2026-10-10 20:59"))
        XCTAssertNil(turn(input(), noon), "The same time is not sent again at once")
    }

    func testTheSameTimeGoesAgainWellInsideTheLease() {
        set(input(), noon)
        XCTAssertLessThan(JobWake.renewEvery * 2, WakeAlarmLimits.lease)
        awake += JobWake.renewEvery - 1
        XCTAssertNil(turn(input(), noon.addingTimeInterval(179)))
        awake += 1
        let again = turn(input(), noon.addingTimeInterval(180))
        XCTAssertEqual(again, seconds("2026-10-10 20:59"))
        wake.answered(.set(again!), for: again!, now: noon.addingTimeInterval(180), awake: awake)
        XCTAssertEqual(kinds, [.alarmSet], "A renewal is no new alarm")
        XCTAssertNil(turn(input(), noon.addingTimeInterval(181)))
    }

    /// The helper is root. A renewal that it refuses waits as a new time
    /// does, and is not sent again at the next turn.
    func testARenewalThatFailsWaitsBeforeItGoesAgain() {
        let waits: [(WakeAlarmResult, TimeInterval)] = [
            (.refused(.tooOften), JobWake.retryAfterTooOften), (.refused(.notCancelled), JobWake.retryAfter),
            (.helperNotAvailable, JobWake.retryAfter),
        ]
        for (result, wait) in waits {
            wake = JobWake()
            awake = 1000
            set(input(), noon)
            awake += JobWake.renewEvery
            let time = seconds("2026-10-10 20:59")
            XCTAssertEqual(turn(input(), noon), time)
            wake.answered(result, for: time, now: noon, awake: awake)
            var calls = 0
            for second in 0..<60 {
                awake += second == 0 ? 0 : 1
                if turn(input(), noon.addingTimeInterval(TimeInterval(second))) != nil { calls += 1 }
            }
            XCTAssertEqual(calls, 0, "\(result): 60 seconds of turns")
            XCTAssertEqual(wake.alarm?.at, at("2026-10-10 20:59"), "Inside the lease the alarm is still there")
            awake += wait - 59
            XCTAssertEqual(turn(input(), noon.addingTimeInterval(wait)), time, "\(result): after the wait")
            wake.answered(result, for: time, now: noon, awake: awake)
            XCTAssertNil(turn(input(), noon.addingTimeInterval(wait)))
            XCTAssertEqual(turn(input(), noon.addingTimeInterval(wait), willSleep: true), time, "Before sleep it goes all the same")
        }
    }

    /// The helper makes the lease no longer for a renewal it refuses,
    /// and takes the alarm away at the end of the lease. The app shows
    /// no alarm then, and the time goes again as a new one.
    func testARenewalThatIsRefusedForTheTimeOfTheLeaseLeavesNoAlarm() {
        set(input(), noon)
        let time = seconds("2026-10-10 20:59")
        awake += JobWake.renewEvery
        XCTAssertEqual(turn(input(), noon), time)
        wake.answered(.refused(.notCancelled), for: time, now: noon, awake: awake)
        XCTAssertEqual(wake.status, .alarmSet(wake.alarm!), "Inside the lease the alarm is still there")
        XCTAssertEqual(kinds, [.alarmSet, .renewalRefused])
        awake += JobWake.retryAfter
        XCTAssertEqual(turn(input(), noon), time)
        wake.answered(.refused(.notCancelled), for: time, now: noon, awake: awake)
        XCTAssertNotNil(wake.alarm)
        XCTAssertEqual(kinds, [.alarmSet, .renewalRefused], "The same refusal is one line")

        awake += WakeAlarmLimits.lease
        XCTAssertEqual(turn(input(), noon), time)
        wake.answered(.refused(.notCancelled), for: time, now: noon, awake: awake)
        XCTAssertNil(wake.alarm)
        XCTAssertNil(wake.memory.owedAlarm)
        XCTAssertFalse(wake.owesCancel)
        XCTAssertEqual(wake.status, .refused(.notCancelled))
        XCTAssertEqual(kinds, [.alarmSet, .renewalRefused, .alarmRefused], "The alarm is gone, and the history says so")
        XCTAssertEqual(wake.memory.history.events.last?.alarmAt, time)
        XCTAssertEqual(wake.memory.history.events.last?.job, "backup")

        // The time is a new one now: it waits for its retry, and no 0
        // goes for an alarm that is not there.
        XCTAssertNil(turn(input(), noon))
        awake += JobWake.retryAfter
        XCTAssertEqual(turn(input(), noon), time)
        wake.answered(.refused(.notCancelled), for: time, now: noon, awake: awake)
        XCTAssertEqual(kinds, [.alarmSet, .renewalRefused, .alarmRefused], "The same refusal is one line")
        awake += JobWake.retryAfter
        set(input(), noon)
        XCTAssertEqual(wake.status, .alarmSet(wake.alarm!))
        XCTAssertEqual(kinds, [.alarmSet, .renewalRefused, .alarmRefused, .alarmSet])
    }

    func testTimeAsleepDoesNotCountForTheRenewal() {
        set(input(), noon)
        sleep(for: 3600)
        XCTAssertNil(turn(input(), noon.addingTimeInterval(3600)), "The lease of the helper counts awake time too")
    }

    func testANewTimeGoesAtOnce() {
        set(input(), noon)
        let edited = input([job("backup", "30 18 * * *")])
        XCTAssertEqual(turn(edited, noon), seconds("2026-10-10 18:29"))
    }

    func testEveryStopTakesTheAlarmAway() {
        var stops: [(String, JobWakeInput, JobWakeStatus)] = []
        var changed = input()
        changed.settings.wakeForJobs = false
        stops.append(("the feature is off", changed, .off))
        changed = input()
        changed.context.enabled = false
        stops.append(("the app is off", changed, .noAlarm(.switchedOff)))
        changed = input()
        changed.context.pausedUntil = noon.addingTimeInterval(600)
        stops.append(("paused", changed, .noAlarm(.paused)))
        changed = input()
        changed.context.safety = .tooHot
        stops.append(("a safety stop", changed, .noAlarm(.safetyStop)))
        changed = input()
        changed.context.onBattery = true
        changed.context.batteryPercent = 90
        stops.append(("on battery", changed, .noAlarm(.onBattery)))
        stops.append(("the job is off", input(on: []), .noAlarm(.noJobSwitchedOn)))
        for (name, stopped, status) in stops {
            wake = JobWake()
            set(input(), noon)
            XCTAssertEqual(turn(stopped, noon), 0, name)
            wake.answered(.cancelled, for: 0, now: noon, awake: awake)
            XCTAssertNil(wake.alarm, name)
            XCTAssertNil(wake.memory.owedAlarm, name)
            XCTAssertEqual(wake.status, status, name)
            XCTAssertEqual(kinds, [.alarmSet, .alarmCancelled], name)
            XCTAssertNil(turn(stopped, noon), "\(name): nothing is left to cancel")
        }
    }

    func testNoCallForAFeatureThatWasNeverOn() {
        XCTAssertNil(turn(JobWakeInput(), noon))
        XCTAssertEqual(wake.status, .off)
        XCTAssertFalse(wake.owesCancel)
    }

    func testAnAlarmOfAnEarlierRunOfTheAppIsTakenAway() {
        wake = JobWake(memory: JobWakeMemory(owedAlarm: seconds("2026-10-10 20:59")))
        XCTAssertEqual(turn(JobWakeInput(), noon), 0)
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(wake.memory.owedAlarm)
        XCTAssertNil(turn(JobWakeInput(), noon))
    }

    // MARK: Sleep

    func testAtWillSleepThePlanIsForAMacThatSleeps() {
        let soon = at("2026-10-10 20:40")
        set(input(), soon)
        XCTAssertEqual(wake.alarm?.fireAt, at("2026-10-11 21:00"), "Awake, the job in 20 minutes needs no alarm")
        set(input(), soon, willSleep: true)
        XCTAssertEqual(wake.alarm?.at, at("2026-10-10 20:59"))
        XCTAssertNil(turn(input(), soon.addingTimeInterval(5)), "A sample before the sleep keeps the alarm")
        wake.wokeInFull()
        XCTAssertNil(turn(input(), soon.addingTimeInterval(10)), "Awake in full again, and the alarm that is set stays")
        XCTAssertEqual(wake.plan.alarm?.at, at("2026-10-10 20:59"))
    }

    func testWillSleepDoesNotWaitForACallThatIsUnderWay() {
        let soon = at("2026-10-10 20:40")
        let first = turn(input(), soon)
        XCTAssertEqual(first, seconds("2026-10-11 20:59"))
        let second = turn(input(), soon, willSleep: true)
        XCTAssertEqual(second, seconds("2026-10-10 20:59"))
        wake.answered(.set(first!), for: first!, now: soon, awake: awake)
        XCTAssertNil(wake.alarm, "The late answer to the first call means nothing")
        wake.answered(.set(second!), for: second!, now: soon, awake: awake)
        XCTAssertEqual(wake.alarm?.at, at("2026-10-10 20:59"))
    }

    /// The Mac sleeps with the alarm set, and wakes by itself 25 seconds
    /// before it, with the display off. The run is too close for a new
    /// alarm, and the alarm that is set stays all the same: it wakes the
    /// Mac, it counts, and its hold opens.
    func testADarkWakeJustBeforeTheAlarmDoesNotMoveIt() {
        let alarm = at("2026-10-10 20:59")
        set(input(), noon)
        awake += 5
        XCTAssertEqual(turn(input(), noon.addingTimeInterval(5), willSleep: true), seconds("2026-10-10 20:59"))
        wake.answered(.set(alarm.timeIntervalSince1970), for: alarm.timeIntervalSince1970, now: noon.addingTimeInterval(5), awake: awake)
        sleep(for: 8 * 3600)
        for before in [TimeInterval(25), 20, 15] {
            awake += 5
            XCTAssertNil(turn(input(), alarm.addingTimeInterval(-before)), "\(before) seconds before the alarm")
            XCTAssertEqual(wake.plan.alarm?.fireAt, at("2026-10-10 21:00"))
            XCTAssertEqual(wake.status, .alarmSet(wake.alarm!))
        }
        awake += 5
        XCTAssertNil(turn(input(), alarm.addingTimeInterval(-10), willSleep: true), "No renewal that the helper would refuse as too close")
        sleep(for: 10)
        turn(input(), alarm.addingTimeInterval(2))
        XCTAssertEqual(kinds, [.alarmSet, .wokeAtAlarm])
        XCTAssertEqual(wake.wakesInLastDay, 1)
        XCTAssertEqual(wake.holds.map(\.fireAt), [seconds("2026-10-10 21:00")])
    }

    /// The turn at "will sleep" and the turn of the timer at the alarm
    /// come with no sample. The power source of the last sample can be
    /// from before the Mac was unplugged, so it is read again for them.
    func testTheTurnsWithNoSampleTakeThePowerSourceAsItIsNow() {
        var stale = input()
        stale.context.batteryPercent = 80
        stale.context.batteryFloorPercent = 30
        let unplugged = FrameContext(onBattery: true, batteryPercent: 79, lidClosed: true, thermalState: 2)
        let fresh = stale.withPower(of: unplugged)
        var want = stale
        want.context.onBattery = true
        want.context.batteryPercent = 79
        XCTAssertEqual(fresh, want, "The power source and the battery, and nothing else")

        // Unplugged, and the lid closed before the next sample.
        set(stale, noon)
        XCTAssertEqual(turn(stale, noon.addingTimeInterval(3), willSleep: true), seconds("2026-10-10 20:59"), "The old values keep the alarm")
        wake = JobWake()
        set(stale, noon)
        XCTAssertEqual(turn(fresh, noon.addingTimeInterval(3), willSleep: true), 0, "On battery the alarm goes before the sleep")
        XCTAssertEqual(wake.status, .noAlarm(.onBattery))

        // Unplugged while the Mac slept, and the timer runs at the alarm.
        wake = JobWake()
        asleep = 0
        set(stale, noon)
        sleep(for: 9 * 3600)
        turn(fresh, at("2026-10-10 20:59").addingTimeInterval(1))
        XCTAssertEqual(wake.holds, [], "No hold on a Mac that can be in a bag")
        XCTAssertEqual(kinds, [.alarmSet, .wokeAtAlarm, .endedOnBattery])

        var plugged = stale
        plugged.context.onBattery = true
        XCTAssertFalse(plugged.withPower(of: FrameContext(onBattery: false, batteryPercent: nil)).context.onBattery)
        XCTAssertNil(plugged.withPower(of: FrameContext()).context.batteryPercent)
    }

    /// The owner of the loop cannot be made in a test, so its source is
    /// read: both turns with no sample pass the power source of now.
    func testTheOwnerReadsThePowerSourceForTheTurnsWithNoSample() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Caffeinagent/StateAggregator.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("jobLoop.willSleep(jobWakeInput.withPower(of: powerContext.context()))"))
        XCTAssertFalse(source.contains("jobLoop.willSleep(jobWakeInput)"))
        let timer = try XCTUnwrap(source.range(of: "private func armJobTimer()"))
        let body = source[timer.upperBound...].prefix(600)
        XCTAssertTrue(body.contains("self?.updateJobWake(powerNow: true)"))
        XCTAssertTrue(source.contains("jobLoop.run(powerNow ? jobWakeInput.withPower(of: powerContext.context()) : jobWakeInput)"))
        // At a full wake a hold can open too.
        XCTAssertTrue(source.contains("jobLoop.wokeInFull(samples > 0 ? jobWakeInput.withPower(of: powerContext.context()) : nil)"))
        XCTAssertFalse(source.contains("jobLoop.wokeInFull()"))
    }

    func testWillSleepRenewsAnAlarmThatIsSet() {
        set(input(), noon)
        XCTAssertEqual(turn(input(), noon.addingTimeInterval(5), willSleep: true), seconds("2026-10-10 20:59"))
    }

    // MARK: The alarms of the last day

    func testAnAlarmThatCameWhileTheMacSleptCounts() {
        set(input(), noon)
        sleep(for: 8 * 3600)
        turn(input(), at("2026-10-10 20:59").addingTimeInterval(3))
        XCTAssertEqual(wake.wakesInLastDay, 1)
        XCTAssertEqual(kinds, [.alarmSet, .wokeAtAlarm])
        XCTAssertEqual(wake.memory.history.events.last?.job, "backup")
        XCTAssertNil(wake.memory.owedAlarm, "macOS used the event up")
    }

    func testAnAlarmWhileTheMacWasAwakeDoesNotCount() {
        set(input(), noon)
        turn(input(), at("2026-10-10 20:59"))
        XCTAssertEqual(wake.wakesInLastDay, 0)
        XCTAssertEqual(kinds, [.alarmSet, .alarmWhileAwake])
        XCTAssertEqual(wake.holds.count, 1, "The hold opens all the same")
    }

    func testAnAlarmThatIsSeenLateCountsAndOpensNoHoldThatIsOver() {
        set(input(), noon)
        sleep(for: 12 * 3600)
        turn(input(), at("2026-10-11 00:30"))
        XCTAssertEqual(wake.wakesInLastDay, 1)
        XCTAssertEqual(kinds, [.alarmSet, .alarmSeenLate])
        XCTAssertEqual(wake.holds, [])
    }

    func testTheLimitOfADayAndItsEnd() {
        var limited = input()
        limited.settings.maxWakesPerDay = 1
        set(limited, noon)
        sleep(for: 8 * 3600)
        XCTAssertNil(turn(limited, at("2026-10-10 20:59")), "The alarm rang, and the limit lets no new one be set")
        XCTAssertEqual(wake.status, .noAlarm(.dailyLimit))
        XCTAssertNil(turn(limited, at("2026-10-11 20:58")))
        XCTAssertNotNil(turn(limited, at("2026-10-11 21:00")), "24 hours after the alarm")
        XCTAssertEqual(wake.wakesInLastDay, 0)
    }

    func testAClockThatWasSetBackForgetsAlarmsAhead() {
        var memory = JobWakeMemory(ledger: [seconds("2026-10-10 11:00"), seconds("2026-10-10 15:00"), seconds("2026-10-09 11:00")])
        memory.prune(now: noon)
        XCTAssertEqual(memory.ledger, [seconds("2026-10-10 11:00")])
    }

    // MARK: The answers of the helper

    func testARefusalIsShownAndTheTimeGoesAgainLater() {
        let time = turn(input(), noon)!
        wake.answered(.refused(.notConfirmed), for: time, now: noon, awake: awake)
        XCTAssertEqual(wake.status, .refused(.notConfirmed))
        XCTAssertNil(wake.alarm)
        XCTAssertEqual(kinds, [.alarmRefused])
        XCTAssertEqual(wake.memory.history.events.last?.reason, WakeAlarmRefusal.notConfirmed.rawValue)
        awake += JobWake.retryAfter - 1
        XCTAssertNil(turn(input(), noon))
        awake += 1
        XCTAssertEqual(turn(input(), noon), time)
        wake.answered(.refused(.notConfirmed), for: time, now: noon, awake: awake)
        XCTAssertEqual(kinds, [.alarmRefused], "The same refusal is one line")
    }

    func testEveryRefusalIsAStatus() {
        for reason in [WakeAlarmRefusal.notATime, .tooSoon, .tooFar, .tooOften, .notScheduled, .notConfirmed, .notCancelled, .unknown] {
            wake = JobWake()
            let time = turn(input(), noon)!
            wake.answered(.refused(reason), for: time, now: noon, awake: awake)
            XCTAssertEqual(wake.status, .refused(reason))
        }
    }

    func testTooOftenWaitsLonger() {
        let time = turn(input(), noon)!
        wake.answered(.refused(.tooOften), for: time, now: noon, awake: awake)
        awake += JobWake.retryAfter
        XCTAssertNil(turn(input(), noon))
        awake += JobWake.retryAfterTooOften
        XCTAssertEqual(turn(input(), noon), time)
    }

    func testARefusalLeavesTheAlarmThatIsSet() {
        set(input(), noon)
        let edited = input([job("backup", "30 18 * * *")])
        let time = turn(edited, noon)!
        wake.answered(.refused(.tooOften), for: time, now: noon, awake: awake)
        XCTAssertEqual(wake.alarm?.at, at("2026-10-10 20:59"))
        XCTAssertEqual(wake.status, .refused(.tooOften))
    }

    /// The helper keeps the old alarm after a refusal, and the old alarm
    /// can be for a job that is off by now. So 0 goes to the helper.
    func testAfterARefusedNewTimeTheOldAlarmIsTakenAway() {
        let both = [job("backup", "0 21 * * *"), job("report", "0 3 * * *")]
        set(input(both, on: ["backup", "report"]), noon)
        XCTAssertEqual(wake.alarm?.jobName, "backup")
        let reportOnly = input(both, on: ["report"])
        let time = turn(reportOnly, noon)!
        XCTAssertEqual(time, seconds("2026-10-11 02:59"))
        wake.answered(.refused(.tooOften), for: time, now: noon, awake: awake)
        XCTAssertEqual(turn(reportOnly, noon), 0, "The alarm of the job that is off must not stay")
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(wake.alarm)
        XCTAssertFalse(wake.owesCancel)
        XCTAssertEqual(wake.status, .refused(.tooOften), "The new time is still not set")
        XCTAssertEqual(kinds, [.alarmSet, .alarmRefused, .alarmCancelled])
        XCTAssertNil(turn(reportOnly, noon), "The new time waits for its retry")
        awake += JobWake.retryAfterTooOften
        XCTAssertEqual(turn(reportOnly, noon), time)
    }

    /// The cancel after a refusal fails too: one try for each try of the
    /// new time, and not one at every turn.
    func testACancelAfterARefusalThatFailsIsTriedAgainWithTheNewTime() {
        set(input(), noon)
        let edited = input([job("backup", "30 18 * * *")])
        let time = turn(edited, noon)!
        wake.answered(.refused(.notScheduled), for: time, now: noon, awake: awake)
        XCTAssertEqual(turn(edited, noon), 0)
        wake.answered(.refused(.notCancelled), for: 0, now: noon, awake: awake)
        XCTAssertTrue(wake.owesCancel)
        XCTAssertEqual(wake.status, .refused(.notScheduled))
        XCTAssertNil(turn(edited, noon))
        XCTAssertNil(turn(edited, noon))
        awake += JobWake.retryAfter
        XCTAssertEqual(turn(edited, noon), time)
        wake.answered(.refused(.notScheduled), for: time, now: noon, awake: awake)
        XCTAssertEqual(turn(edited, noon), 0)
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(turn(edited, noon))
        XCTAssertEqual(kinds, [.alarmSet, .alarmRefused, .alarmCancelled], "The same refusal is one line")
    }

    /// A daily job and a monthly job are on, and the daily one is switched
    /// off. The helper takes no time that is more than 8 days ahead, so
    /// none is asked for, and the alarm of the daily job goes.
    /// The 0 after a refused time gets no answer. The refused time still
    /// waits for its retry: it does not go again at the next turn.
    func testACancelAfterARefusalThatGetsNoAnswerKeepsTheWaitOfTheRefusedTime() {
        set(input(), noon)
        let edited = input([job("backup", "30 18 * * *")])
        let time = turn(edited, noon)!
        wake.answered(.refused(.notScheduled), for: time, now: noon, awake: awake)
        XCTAssertEqual(turn(edited, noon), 0)
        wake.answered(.helperNotAvailable, for: 0, now: noon, awake: awake)
        XCTAssertEqual(wake.status, .helperSilent)
        XCTAssertEqual(kinds, [.alarmSet, .alarmRefused, .helperSilent])
        XCTAssertEqual(wake.alarm?.at, at("2026-10-10 20:59"), "Inside the lease the old alarm can still be there")
        var calls: [TimeInterval] = []
        for second in 1..<Int(JobWake.retryAfter) {
            awake += 1
            if let call = turn(edited, noon.addingTimeInterval(TimeInterval(second))) { calls.append(call) }
        }
        XCTAssertEqual(calls, [], "No call in the 59 seconds after")
        XCTAssertEqual(kinds, [.alarmSet, .alarmRefused, .helperSilent])
        awake += 1
        XCTAssertEqual(turn(edited, noon.addingTimeInterval(60)), time, "The retry of the refused time")
        wake.answered(.refused(.notScheduled), for: time, now: noon, awake: awake)
        XCTAssertEqual(kinds, [.alarmSet, .alarmRefused, .helperSilent], "The same refusal is one line")
        XCTAssertEqual(turn(edited, noon.addingTimeInterval(60)), 0, "One cancel for each try")

        // The lease rule counts for this answer too.
        awake += WakeAlarmLimits.lease
        wake.answered(.helperNotAvailable, for: 0, now: noon, awake: awake)
        XCTAssertNil(wake.alarm, "The helper took it away itself, or is gone with it")
        XCTAssertFalse(wake.owesCancel)
    }

    /// The answer to the 0 after a refused time is lost, and the Mac
    /// goes to sleep before the refused time is tried again. The old
    /// alarm can be for a job that is off, so 0 goes once more.
    func testAtWillSleepTheCancelAfterARefusalGoesAgain() {
        let both = [job("backup", "0 21 * * *"), job("report", "0 3 * * *")]
        set(input(both, on: ["backup", "report"]), noon)
        let reportOnly = input(both, on: ["report"])
        let time = turn(reportOnly, noon)!
        wake.answered(.refused(.tooOften), for: time, now: noon, awake: awake)
        XCTAssertEqual(turn(reportOnly, noon), 0)
        wake.answered(.helperNotAvailable, for: 0, now: noon, awake: awake)
        XCTAssertEqual(wake.alarm?.jobName, "backup")
        XCTAssertNil(turn(reportOnly, noon), "Awake, one cancel for each try")
        XCTAssertEqual(turn(reportOnly, noon, willSleep: true), 0, "Before sleep the cancel goes again")
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(wake.alarm)
        XCTAssertFalse(wake.owesCancel)
        XCTAssertEqual(wake.status, .refused(.tooOften), "The refusal of the new time is still what is known")
        XCTAssertNil(turn(reportOnly, noon), "The new time waits for its retry")
        XCTAssertEqual(turn(reportOnly, noon, willSleep: true), time, "With no alarm left, the time goes again before sleep")
    }

    /// No alarm is wanted, and the 0 failed: it waits for its retry while
    /// the Mac is awake, and goes again when the Mac goes to sleep.
    func testAtWillSleepACancelThatFailedGoesAgain() {
        set(input(), noon)
        let off = input(on: [])
        for result in [WakeAlarmResult.refused(.notCancelled), .helperNotAvailable] {
            XCTAssertEqual(turn(off, noon, willSleep: result == .helperNotAvailable), 0)
            wake.answered(result, for: 0, now: noon, awake: awake)
            XCTAssertTrue(wake.owesCancel)
            XCTAssertNil(turn(off, noon), "\(result): awake, it waits")
        }
        XCTAssertEqual(turn(off, noon, willSleep: true), 0)
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(turn(off, noon, willSleep: true), "No alarm is left")
    }

    func testAJobThatIsTooFarAheadTakesTheOldAlarmAwayAndAsksForNone() {
        let both = [job("backup", "0 21 * * *"), job("monthly", "0 3 1 * *")]
        set(input(both, on: ["backup", "monthly"]), noon)
        let monthlyOnly = input(both, on: ["monthly"])
        XCTAssertEqual(turn(monthlyOnly, noon), 0)
        XCTAssertEqual(wake.plan.noAlarm, .tooFarAhead)
        wake.answered(.cancelled, for: 0, now: noon, awake: awake)
        XCTAssertNil(wake.alarm)
        XCTAssertEqual(wake.status, .noAlarm(.tooFarAhead))
        for _ in 0..<20 {
            awake += JobWake.retryAfter
            XCTAssertNil(turn(monthlyOnly, noon), "Nothing is asked for every minute")
        }
        XCTAssertEqual(turn(monthlyOnly, at("2026-10-25 12:00")), seconds("2026-11-01 02:59"), "Inside 8 days the alarm is set")
    }

    /// A helper of a build before alarms does not know the call, and a
    /// helper that is gone gives no answer. Both are the same result.
    func testAHelperThatGivesNoAnswer() {
        let time = turn(input(), noon)!
        wake.answered(.helperNotAvailable, for: time, now: noon, awake: awake)
        XCTAssertEqual(wake.status, .helperSilent)
        XCTAssertEqual(kinds, [.helperSilent])
        XCTAssertNil(turn(input(), noon))
        awake += JobWake.retryAfter
        XCTAssertEqual(turn(input(), noon), time, "It is asked again: the helper may be the new one by now")
        wake.answered(.helperNotAvailable, for: time, now: noon, awake: awake)
        XCTAssertEqual(kinds, [.helperSilent], "One line for one silence")
        awake += JobWake.retryAfter
        set(input(), noon)
        XCTAssertEqual(kinds, [.helperSilent, .alarmSet])
        XCTAssertEqual(wake.status, .alarmSet(wake.alarm!))
    }

    func testACancelThatGetsNoAnswerIsOverWithTheLease() {
        set(input(), noon)
        var off = input()
        off.settings.wakeForJobs = false
        XCTAssertEqual(turn(off, noon), 0)
        wake.answered(.helperNotAvailable, for: 0, now: noon, awake: awake)
        XCTAssertTrue(wake.owesCancel, "Inside the lease the alarm can still be there")
        awake += WakeAlarmLimits.lease
        XCTAssertEqual(turn(off, noon), 0)
        wake.answered(.helperNotAvailable, for: 0, now: noon, awake: awake)
        XCTAssertFalse(wake.owesCancel, "The helper took it away itself, or is gone with it")
        XCTAssertNil(turn(off, noon))
    }

    func testNoCallWithoutTheHelperOrOutsideTheApplicationsFolder() {
        var noHelper = input()
        noHelper.helperEnabled = false
        XCTAssertNil(turn(noHelper, noon))
        XCTAssertEqual(wake.status, .needsHelper)
        var elsewhere = input()
        elsewhere.inApplications = false
        XCTAssertNil(turn(elsewhere, noon))
        XCTAssertEqual(wake.status, .needsApplications)
        XCTAssertEqual(wake.plan.nextRuns.map(\.job.name), ["backup"], "The jobs are listed all the same")
    }

    func testAHelperThatWasSwitchedOffTookItsAlarmAlong() {
        set(input(), noon)
        var noHelper = input()
        noHelper.helperEnabled = false
        XCTAssertNil(turn(noHelper, noon))
        XCTAssertNil(wake.alarm)
        XCTAssertFalse(wake.owesCancel)
        XCTAssertEqual(turn(input(), noon), seconds("2026-10-10 20:59"), "Allowed again, it gets the time again")
    }

    func testAfterTheHelperWasReplacedTheTimeGoesAgain() {
        set(input(), noon)
        wake.helperReplaced()
        XCTAssertNil(wake.alarm)
        XCTAssertEqual(turn(input(), noon), seconds("2026-10-10 20:59"))
    }

    func testQuitOwesACancelOnlyWithAnAlarm() {
        XCTAssertFalse(wake.owesCancel)
        set(input(), noon)
        XCTAssertTrue(wake.owesCancel)
        wake.cancelled(.cancelled, now: noon)
        XCTAssertFalse(wake.owesCancel)
        XCTAssertEqual(kinds, [.alarmSet, .alarmCancelled])
    }

    // MARK: Memory

    func testTheMemoryIsSavedAndReadAndHoldsNoMoreThanFiftyEvents() {
        let defaults = TestDefaults()
        XCTAssertEqual(JobWakeMemoryStore.load(from: defaults), JobWakeMemory())
        var memory = JobWakeMemory(ledger: [1, 2], owedAlarm: 3)
        for index in 0..<60 { memory.history.note(.alarmSet, at: noon.addingTimeInterval(TimeInterval(index)), alarmAt: 5, job: "backup") }
        XCTAssertEqual(memory.history.events.count, JobHistory.limit)
        XCTAssertEqual(memory.history.events.first?.at, noon.timeIntervalSince1970 + 10)
        JobWakeMemoryStore.save(memory, to: defaults)
        XCTAssertEqual(JobWakeMemoryStore.load(from: defaults), memory)
        defaults.set(Data("no json".utf8), forKey: JobWakeMemoryStore.key)
        XCTAssertEqual(JobWakeMemoryStore.load(from: defaults), JobWakeMemory())
    }

    func testAnEventHoldsItsTimeItsKindAndTheShortNameOnly() throws {
        XCTAssertEqual(Mirror(reflecting: JobEvent(at: 0, kind: .alarmSet)).children.map { $0.label ?? "" }, ["at", "kind", "alarmAt", "job", "reason"])
        var history = JobHistory()
        history.note(.jobSeen, at: noon, job: "a name\nwith a line break " + String(repeating: "x", count: 200))
        let name = try XCTUnwrap(history.events.first?.job)
        XCTAssertFalse(name.contains("\n"))
        XCTAssertEqual(name.count, ScheduledJob.nameLimit)
    }
}
