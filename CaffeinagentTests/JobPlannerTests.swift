import XCTest

final class JobPlannerTests: XCTestCase {
    private let clock = JobTime.clock()
    /// A Saturday.
    private let now = JobTime.date("2026-10-10 12:00")

    private func at(_ text: String) -> Date { JobTime.date(text) }

    private func job(_ name: String, _ cron: String, on: Bool = true) -> ScheduledJob {
        ScheduledJob(id: "crontab:\(name)", source: .crontab, name: name, schedule: .cron(JobTime.cron(cron)), enabled: on)
    }

    private var settings: JobSettings {
        var settings = JobSettings()
        settings.wakeForJobs = true
        return settings
    }

    private func plan(
        _ jobs: [ScheduledJob], settings: JobSettings? = nil, context: JobPlanContext = JobPlanContext(), now: Date? = nil
    ) -> JobPlan {
        JobPlanner.plan(jobs: jobs, settings: settings ?? self.settings, context: context, now: now ?? self.now, clock: clock)
    }

    // MARK: The alarm

    func testTheNearestJobThatIsOnGetsTheAlarm() {
        let jobs = [job("late", "0 3 * * *"), job("early", "0 21 * * *"), job("off", "0 15 * * *", on: false)]
        let plan = self.plan(jobs)
        XCTAssertEqual(plan.alarm, JobAlarm(at: at("2026-10-10 20:59"), fireAt: at("2026-10-10 21:00"), jobID: "crontab:early", jobName: "early"))
        XCTAssertNil(plan.noAlarm)
        XCTAssertEqual(plan.nextRuns.map(\.job.name), ["off", "early", "late"], "Every job, the next to run first")
        XCTAssertEqual(plan.nextRuns.map(\.fireAt), [at("2026-10-10 15:00"), at("2026-10-10 21:00"), at("2026-10-11 03:00")])
    }

    func testTheLeadTime() {
        var settings = settings
        XCTAssertEqual(settings.leadTime, 60)
        settings.leadTime = 300
        XCTAssertEqual(plan([job("a", "0 21 * * *")], settings: settings).alarm?.at, at("2026-10-10 20:55"))
        XCTAssertEqual(plan([job("a", "0 21 * * *")], settings: settings).alarm?.fireAt, at("2026-10-10 21:00"))
    }

    func testOnlyOneAlarmAndTheNextOneAfterIt() {
        let jobs = [job("a", "0 21 * * *"), job("b", "0 3 * * *")]
        XCTAssertEqual(plan(jobs).alarm?.jobName, "a")
        XCTAssertEqual(plan(jobs, now: at("2026-10-10 21:00")).alarm?.fireAt, at("2026-10-11 03:00"), "After the job ran")
        XCTAssertEqual(plan(jobs, now: at("2026-10-11 03:00")).alarm?.fireAt, at("2026-10-11 21:00"))
    }

    func testTheAlarmMovesWhenAJobIsEditedOrSwitchedOff() {
        var jobs = [job("a", "0 21 * * *"), job("b", "0 3 * * *")]
        XCTAssertEqual(plan(jobs).alarm?.at, at("2026-10-10 20:59"))
        jobs[0].schedule = .cron(JobTime.cron("30 18 * * *"))
        XCTAssertEqual(plan(jobs).alarm?.at, at("2026-10-10 18:29"), "Edited")
        jobs[0].enabled = false
        XCTAssertEqual(plan(jobs).alarm, JobAlarm(at: at("2026-10-11 02:59"), fireAt: at("2026-10-11 03:00"), jobID: "crontab:b", jobName: "b"))
        jobs[1].enabled = false
        XCTAssertNil(plan(jobs).alarm)
        XCTAssertEqual(plan(jobs).noAlarm, .noJobSwitchedOn)
        XCTAssertEqual(plan([]).noAlarm, .noJobSwitchedOn)
        XCTAssertEqual(plan([]).nextRuns, [])
    }

    func testTheSwitchesOfTheUserDecideWhichJobsAreOn() {
        let found = [job("a", "0 21 * * *", on: false), job("b", "0 3 * * *", on: false)]
        var settings = settings
        XCTAssertEqual(plan(settings.applied(to: found), settings: settings).noAlarm, .noJobSwitchedOn, "Nothing is adopted by itself")
        settings.set(true, for: "crontab:b")
        XCTAssertEqual(plan(settings.applied(to: found), settings: settings).alarm?.jobID, "crontab:b")
    }

    func testAJobInTheNextHalfHourNeedsNoAlarmWhileTheMacIsAwake() {
        let jobs = [job("soon", "20 12 * * *"), job("later", "0 15 * * *")]
        XCTAssertEqual(plan(jobs).alarm?.jobName, "later")
        XCTAssertEqual(plan(jobs).nextRuns.first?.job.name, "soon", "It is still in the list")
        XCTAssertEqual(plan([jobs[0]]).alarm?.fireAt, at("2026-10-11 12:20"), "Its run of tomorrow")
        XCTAssertEqual(plan([job("edge", "30 12 * * *")]).alarm?.fireAt, at("2026-10-11 12:30"), "Half an hour away is inside")
        XCTAssertEqual(plan([job("past", "31 12 * * *")]).alarm?.fireAt, at("2026-10-10 12:31"))
    }

    func testAboutToSleepTheNearJobGetsTheAlarm() {
        let asleep = JobPlanContext(macAwake: false)
        let jobs = [job("soon", "20 12 * * *"), job("later", "0 15 * * *")]
        XCTAssertEqual(plan(jobs, context: asleep).alarm, JobAlarm(at: at("2026-10-10 12:19"), fireAt: at("2026-10-10 12:20"), jobID: "crontab:soon", jobName: "soon"))
        // The helper takes no alarm that is less than 30 seconds ahead.
        XCTAssertEqual(plan([job("now", "1 12 * * *"), jobs[1]], context: asleep).alarm?.jobName, "later", "The alarm would be now")
        let almost = at("2026-10-10 12:00").addingTimeInterval(29)
        XCTAssertEqual(plan([job("two", "2 12 * * *")], context: asleep, now: almost).alarm?.at, at("2026-10-10 12:01"), "31 seconds ahead")
        XCTAssertEqual(plan([job("two", "2 12 * * *")], context: asleep, now: almost.addingTimeInterval(1)).alarm?.fireAt, at("2026-10-11 12:02"))
    }

    /// The rule for a run that is too close is for a new alarm. An alarm
    /// that is set stays while its job is on and its run is ahead.
    func testAnAlarmThatIsSetStaysThoughItsRunIsClose() {
        let jobs = [job("soon", "20 12 * * *"), job("later", "0 15 * * *")]
        let set = JobAlarm(at: at("2026-10-10 12:19"), fireAt: at("2026-10-10 12:20"), jobID: "crontab:soon", jobName: "soon")
        let close = at("2026-10-10 12:19").addingTimeInterval(-25)
        for awake in [true, false] {
            var context = JobPlanContext(macAwake: awake)
            XCTAssertEqual(plan(jobs, context: context, now: close).alarm?.jobName, "later", "No new alarm that close")
            context.alarmSet = set
            XCTAssertEqual(plan(jobs, context: context, now: close).alarm, set)
            XCTAssertEqual(plan(jobs, context: context, now: at("2026-10-10 12:19").addingTimeInterval(30)).alarm, set, "Up to the time of the job")
            XCTAssertEqual(plan(jobs, context: context, now: at("2026-10-10 12:20")).alarm?.jobName, "later", "The run is not ahead any more")
            var off = jobs
            off[0].enabled = false
            XCTAssertEqual(plan(off, context: context, now: close).alarm?.jobName, "later", "The job was switched off")
            var edited = jobs
            edited[0].schedule = .cron(JobTime.cron("21 12 * * *"))
            XCTAssertNotEqual(plan(edited, context: context, now: close).alarm, set, "The job runs at another time now")
            var stopped = context
            stopped.enabled = false
            XCTAssertNil(plan(jobs, context: stopped, now: close).alarm, "A stop takes it away")
        }
        var context = JobPlanContext()
        context.alarmSet = set
        var settings = settings
        settings.leadTime = 300
        XCTAssertEqual(plan(jobs, settings: settings, context: context, now: at("2026-10-10 11:00")).alarm?.at, at("2026-10-10 12:15"), "Far ahead a new lead time moves it")
    }

    func testAJobThatRunsTooOftenIsListedAndGetsNoAlarm() {
        let jobs = [job("often", "*/10 * * * *"), job("daily", "0 21 * * *")]
        let plan = self.plan(jobs)
        XCTAssertEqual(plan.alarm?.jobName, "daily")
        XCTAssertEqual(plan.nextRuns.map(\.tooOften), [true, false])
        XCTAssertEqual(self.plan([jobs[0]]).noAlarm, .noJobSwitchedOn)
        XCTAssertNotNil(self.plan([job("half", "*/30 * * * *")]).alarm, "Every half hour is offered")
    }

    func testAJobWithNoKnownRun() {
        let never = job("never", "0 0 30 2 *")
        let plan = self.plan([never, job("daily", "0 21 * * *", on: false)])
        XCTAssertNil(plan.alarm)
        XCTAssertEqual(plan.noAlarm, .noRunKnown)
        XCTAssertEqual(plan.nextRuns.map(\.job.name), ["daily", "never"], "Last in the list")
        let interval = ScheduledJob(id: "hermes:x", source: .hermes, name: "x", schedule: .reported(ReportedSchedule(nextRun: at("2026-10-01 00:00"), everyMinutes: 360)), enabled: true)
        XCTAssertEqual(self.plan([interval]).noAlarm, .noRunKnown, "The time Hermes wrote is over")
    }

    func testNoAlarmForAJobThatIsMoreThanEightDaysAhead() {
        let monthly = job("monthly", "0 3 1 * *")
        let plan = self.plan([monthly])
        XCTAssertNil(plan.alarm, "The helper would refuse it")
        XCTAssertEqual(plan.noAlarm, .tooFarAhead)
        XCTAssertEqual(plan.nextRuns.map(\.fireAt), [at("2026-11-01 03:00")], "It is still in the list")
        let edge = at("2026-10-24 02:59")
        XCTAssertEqual(self.plan([monthly], now: edge).alarm?.at, at("2026-11-01 02:59"), "8 days ahead to the second")
        XCTAssertEqual(self.plan([monthly], now: edge.addingTimeInterval(-1)).noAlarm, .tooFarAhead)
        XCTAssertEqual(self.plan([monthly, job("daily", "0 21 * * *")]).alarm?.jobName, "daily")
    }

    /// A monthly job runs in 20 minutes and the Mac is awake: that run
    /// needs no alarm, and the one after it is next month. So the line
    /// of Settings cannot say that the next job is 8 days away.
    func testAMonthlyJobThatRunsSoonOnAnAwakeMacIsTooFarAhead() {
        let monthly = job("monthly", "20 12 10 * *")
        let plan = self.plan([monthly])
        XCTAssertEqual(plan.nextRuns.map(\.fireAt), [at("2026-10-10 12:20")], "The next run is in 20 minutes")
        XCTAssertNil(plan.alarm)
        XCTAssertEqual(plan.noAlarm, .tooFarAhead, "The run to wake for is the one of November")
        let line = PanelText.jobStatus(.noAlarm(.tooFarAhead), settings: settings, now: now)
        XCTAssertEqual(line, "No wake is set yet: the next run to wake for is more than 8 days away.")
        XCTAssertFalse(line?.contains("next job") ?? true)
        let asleep = self.plan([monthly], context: JobPlanContext(macAwake: false))
        XCTAssertEqual(asleep.alarm?.fireAt, at("2026-10-10 12:20"), "About to sleep, the near run gets the alarm")
    }

    func testTheTimeAHermesJobReports() {
        let reported = ScheduledJob(id: "hermes:x", source: .hermes, name: "Briefing", schedule: .reported(ReportedSchedule(nextRun: at("2026-10-10 17:45"), everyMinutes: 360)), enabled: true)
        XCTAssertEqual(plan([reported, job("daily", "0 21 * * *")]).alarm, JobAlarm(at: at("2026-10-10 17:44"), fireAt: at("2026-10-10 17:45"), jobID: "hermes:x", jobName: "Briefing"))
    }

    // MARK: No alarm

    func testEveryStopStopsTheAlarm() {
        let jobs = [job("a", "0 21 * * *")]
        var off = settings
        off.wakeForJobs = false
        XCTAssertEqual(plan(jobs, settings: off).noAlarm, .featureOff)
        XCTAssertEqual(plan(jobs, settings: JobSettings()).noAlarm, .featureOff, "Off until the user switches it on")
        let stops: [(JobPlanContext, NoAlarmReason)] = [
            (JobPlanContext(enabled: false), .switchedOff),
            (JobPlanContext(pausedUntil: at("2026-10-10 12:30")), .paused),
            (JobPlanContext(entitlement: .expired(.trialOver)), .notEntitled),
            (JobPlanContext(safety: .tooHot), .safetyStop),
            (JobPlanContext(safety: .batteryLow(percent: 18)), .safetyStop),
            (JobPlanContext(safety: .weakCharger(percent: 18)), .safetyStop),
            (JobPlanContext(enabled: false, safety: .tooHot), .safetyStop),
        ]
        for (context, reason) in stops {
            let plan = self.plan(jobs, context: context)
            XCTAssertNil(plan.alarm, "\(reason)")
            XCTAssertEqual(plan.noAlarm, reason)
            XCTAssertEqual(plan.nextRuns.count, 1, "The list is still there")
        }
        XCTAssertNotNil(plan(jobs, context: JobPlanContext(pausedUntil: at("2026-10-10 11:00"))).alarm, "A pause that is over")
        XCTAssertNotNil(plan(jobs, context: JobPlanContext(entitlement: .trial(daysLeft: 1))).alarm)
        XCTAssertNotNil(plan(jobs, context: JobPlanContext(entitlement: .licensed)).alarm)
    }

    func testOnBatteryThereIsNoAlarmUnlessTheUserAllowsIt() {
        let jobs = [job("a", "0 21 * * *")]
        XCTAssertTrue(JobSettings().onPowerOnly)
        XCTAssertEqual(plan(jobs, context: JobPlanContext(onBattery: true, batteryPercent: 90)).noAlarm, .onBattery)
        XCTAssertNotNil(plan(jobs, context: JobPlanContext(onBattery: false, batteryPercent: 90)).alarm)
        var settings = settings
        settings.onPowerOnly = false
        XCTAssertNotNil(plan(jobs, settings: settings, context: JobPlanContext(onBattery: true, batteryPercent: 90)).alarm)
    }

    func testNoAlarmWithinFivePointsOfTheBatteryFloor() {
        let jobs = [job("a", "0 21 * * *")]
        var settings = settings
        settings.onPowerOnly = false
        func reason(_ percent: Int?, floor: Int = 20, floorOn: Bool = true, onBattery: Bool = true) -> NoAlarmReason? {
            plan(jobs, settings: settings, context: JobPlanContext(
                onBattery: onBattery, batteryPercent: percent, batteryFloorEnabled: floorOn, batteryFloorPercent: floor
            )).noAlarm
        }
        XCTAssertNil(reason(26))
        XCTAssertEqual(reason(25), .batteryLow)
        XCTAssertEqual(reason(20), .batteryLow)
        XCTAssertEqual(reason(3), .batteryLow)
        XCTAssertNil(reason(41, floor: 35))
        XCTAssertEqual(reason(40, floor: 35), .batteryLow)
        XCTAssertEqual(reason(nil), .batteryUnknown, "A level that was not read is not a full battery")
        XCTAssertEqual(reason(90, floorOn: false), .batteryFloorOff, "Nothing would stop a Mac that woke itself")
        XCTAssertNil(reason(22, onBattery: false), "On power the level does not count")
        XCTAssertNil(reason(nil, onBattery: false), "A Mac without a battery")
        XCTAssertNil(reason(90, floorOn: false, onBattery: false))
    }

    func testNoMoreAlarmsThanTheLimitOfADay() {
        let jobs = [job("a", "0 21 * * *")]
        XCTAssertEqual(JobSettings().maxWakesPerDay, 12)
        XCTAssertNotNil(plan(jobs, context: JobPlanContext(wakesInLastDay: 11)).alarm)
        XCTAssertEqual(plan(jobs, context: JobPlanContext(wakesInLastDay: 12)).noAlarm, .dailyLimit)
        var settings = settings
        settings.maxWakesPerDay = 2
        XCTAssertEqual(plan(jobs, settings: settings, context: JobPlanContext(wakesInLastDay: 2)).noAlarm, .dailyLimit)
        XCTAssertNotNil(plan(jobs, settings: settings, context: JobPlanContext(wakesInLastDay: 1)).alarm)
    }

    func testTheSameInputGivesTheSamePlan() {
        let jobs = [job("b", "0 21 * * *"), job("a", "0 21 * * *")]
        XCTAssertEqual(plan(jobs), plan(jobs))
        XCTAssertEqual(plan(jobs).alarm?.jobName, "b", "Of two jobs at one time, the first that was found")
    }
}
