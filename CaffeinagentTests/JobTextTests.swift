import XCTest

/// The words of "Wake for jobs" in Settings and in the menu.
final class JobTextTests: XCTestCase {
    private let now = JobTime.date("2026-10-10 12:00")
    private let locale = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(_ text: String) -> Date { JobTime.date(text) }

    private func run(_ name: String = "backup.sh", _ source: ScheduledJob.Source = .crontab, fireAt: Date?, tooOften: Bool = false) -> JobRun {
        JobRun(job: ScheduledJob(id: "\(source.rawValue):\(name)", source: source, name: name, schedule: .cron(JobTime.cron("0 3 * * *"))), fireAt: fireAt, tooOften: tooOften)
    }

    private func alarm(_ time: String, _ name: String = "backup.sh") -> JobAlarm {
        JobAlarm(at: at(time), fireAt: at(time).addingTimeInterval(60), jobID: "crontab:\(name)", jobName: name)
    }

    private func status(_ status: JobWakeStatus, _ settings: JobSettings = JobSettings()) -> String? {
        PanelText.jobStatus(status, settings: settings, now: now, calendar: calendar, locale: locale)
    }

    // MARK: Settings

    func testWhatTheSwitchDoes() {
        XCTAssertEqual(PanelText.jobsTitle, "Wake for jobs")
        XCTAssertEqual(
            PanelText.jobsExplained(leadTime: JobSettings().leadTime),
            "Wakes your Mac 1 minute before a job, keeps it awake until the job ends, then lets it sleep."
        )
        XCTAssertEqual(PanelText.jobsExplained(leadTime: 300), "Wakes your Mac 5 minutes before a job, keeps it awake until the job ends, then lets it sleep.")
        XCTAssertEqual(PanelText.jobsExplained(leadTime: 30), "Wakes your Mac 30 seconds before a job, keeps it awake until the job ends, then lets it sleep.")
        XCTAssertEqual(PanelText.jobsOnPowerOnly, "Only on power")
        XCTAssertEqual(PanelText.jobsOnPowerExplained, "On battery, Agent Caffeine sets no wake and keeps your Mac awake for no job.")
        XCTAssertEqual(PanelText.jobsOnBatteryWarning, "On battery with the lid closed this is not tested yet. Your Mac can wake in a bag.")
        XCTAssertEqual(PanelText.jobsShowHistory, "Show history")
    }

    func testTheLineOfAJob() {
        func detail(_ run: JobRun) -> String { PanelText.jobDetail(run, now: now, calendar: calendar, locale: locale) }
        XCTAssertEqual(detail(run(fireAt: at("2026-10-10 21:00"))), "crontab · next run at 21:00")
        XCTAssertEqual(detail(run("com.example.daily", .launchd, fireAt: at("2026-10-11 03:00"))), "launchd agent · next run tomorrow at 03:00")
        XCTAssertEqual(detail(run("Digest", .hermes, fireAt: at("2026-10-14 07:30"))), "Hermes Agent · next run on Wed, Oct 14 at 07:30")
        XCTAssertEqual(detail(run(fireAt: nil)), "crontab · No next run is known")
        XCTAssertEqual(detail(run(fireAt: at("2026-10-10 12:05"), tooOften: true)), "crontab · Runs too often to wake for")
    }

    func testTheTimeFollowsTheClockOfTheUser() {
        let american = Locale(identifier: "en_US")
        XCTAssertEqual(PanelText.when(at("2026-10-10 21:00"), now: now, calendar: calendar, locale: american).replacingOccurrences(of: "\u{202F}", with: " "), "at 9:00 PM")
    }

    func testEveryStatusIsOnePlainLine() {
        XCTAssertNil(status(.off))
        XCTAssertNil(status(.noAlarm(.featureOff)))
        XCTAssertEqual(status(.needsApplications), PanelText.moveToApplicationsToUse)
        XCTAssertEqual(status(.needsHelper), "This needs the helper. Set it up under Lid closed first.")
        XCTAssertEqual(status(.helperSilent), "The helper gave no answer. It can be from an older version. Quit Agent Caffeine and open it again.")
        XCTAssertEqual(status(.asking), "Setting the wake time…")
        XCTAssertEqual(status(.alarmSet(alarm("2026-10-10 20:59"))), "Next wake at 20:59 for backup.sh.")
        XCTAssertEqual(status(.alarmSet(alarm("2026-10-11 02:59"))), "Next wake tomorrow at 02:59 for backup.sh.")
        XCTAssertEqual(status(.refused(.tooOften)), "The helper did not set the wake time: the time changed too often in one hour. Agent Caffeine tries again.")
        XCTAssertEqual(status(.noAlarm(.onBattery)), "No wake is set while your Mac is on battery.")
        XCTAssertEqual(status(.noAlarm(.noJobSwitchedOn)), "Switch on a job, and Agent Caffeine wakes your Mac for it.")
        XCTAssertEqual(status(.noAlarm(.tooFarAhead)), "No wake is set yet: the next job is more than 8 days away.")
        var settings = JobSettings()
        settings.maxWakesPerDay = 12
        XCTAssertEqual(status(.noAlarm(.dailyLimit), settings), "No wake is set: your Mac was woken 12 times in the last 24 hours.")
    }

    /// Every line of the feature, to check the style of all of them.
    private var allLines: [String] {
        let reasons: [NoAlarmReason] = [
            .safetyStop, .switchedOff, .paused, .notEntitled, .onBattery, .batteryFloorOff, .batteryUnknown, .batteryLow, .dailyLimit,
            .noJobSwitchedOn, .noRunKnown, .tooFarAhead,
        ]
        let refusals: [WakeAlarmRefusal] = [.notATime, .tooSoon, .tooFar, .tooOften, .notScheduled, .notConfirmed, .notCancelled, .unknown]
        var lines = reasons.compactMap { status(.noAlarm($0)) } + refusals.compactMap { status(.refused($0)) }
        XCTAssertEqual(lines.count, reasons.count + refusals.count, "Each has a line")
        lines += [status(.needsApplications), status(.needsHelper), status(.helperSilent), status(.asking), status(.alarmSet(alarm("2026-10-10 20:59")))].compactMap { $0 }
        lines += JobEvent.Kind.allCases.map {
            PanelText.jobEvent(JobEvent(at: 0, kind: $0, alarmAt: at("2026-10-10 20:59").timeIntervalSince1970, job: "backup.sh", reason: 4), calendar: calendar, locale: locale)
        }
        lines += JobEvent.Kind.allCases.map { PanelText.jobEvent(JobEvent(at: 0, kind: $0), calendar: calendar, locale: locale) }
        lines += ScheduledJob.Source.allCases.map(PanelText.jobSourceUnreadable)
        lines += [
            PanelText.jobsTitle, PanelText.jobsSwitch, PanelText.jobsNoneFound, PanelText.jobsPerJob, PanelText.jobsOnPowerOnly,
            PanelText.jobsOnPowerExplained, PanelText.jobsOnBatteryWarning, PanelText.jobsShowHistory, PanelText.jobsHideHistory, PanelText.jobsNoHistory,
            PanelText.jobsTooOften, PanelText.jobsNoRunKnown, PanelText.jobsNeedHelper, PanelText.jobsExplained(leadTime: 60), PanelText.jobHoldHint,
            PanelText.jobNoSwitch(.sameLines), PanelText.jobNoSwitch(.noPlainName),
            PanelText.wakesAt(alarm("2026-10-10 20:59"), now: now, calendar: calendar, locale: locale),
        ]
        return lines
    }

    func testTheStyleOfEveryLine() {
        let lines = allLines
        XCTAssertGreaterThan(lines.count, 60)
        for line in lines {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"), "No dash: \(line)")
            XCTAssertFalse(line.contains("*"), "No bold: \(line)")
            XCTAssertFalse(line.contains("\n"), line)
            XCTAssertNil(line.range(of: #"\b\d+ ?(min|mins|sec|secs|hr|hrs|h|m|s)\b"#, options: .regularExpression), "Units in full words: \(line)")
            XCTAssertNil(line.range(of: "agent caffeine"), "The brand: \(line)")
            // A line that begins with the name of a job begins as the name does.
            if !line.hasPrefix("backup.sh") { XCTAssertEqual(String(line.prefix(1)), line.prefix(1).uppercased(), "Sentence case: \(line)") }
            XCTAssertNil(line.range(of: #"[A-Za-z] [A-Z][a-z]+ [A-Z][a-z]+ [A-Z][a-z]+"#, options: .regularExpression), "No title case: \(line)")
        }
    }

    func testTheLinesOfTheHistory() {
        func line(_ kind: JobEvent.Kind, alarm: String? = "2026-10-10 20:59", job: String? = "backup.sh", reason: Int? = nil) -> String {
            PanelText.jobEvent(JobEvent(at: 0, kind: kind, alarmAt: alarm.map { at($0).timeIntervalSince1970 }, job: job, reason: reason), calendar: calendar, locale: locale)
        }
        XCTAssertEqual(line(.alarmSet), "Wake at 20:59 set for backup.sh")
        XCTAssertEqual(line(.alarmSet, alarm: nil, job: nil), "Wake set")
        XCTAssertEqual(line(.alarmRefused, reason: WakeAlarmRefusal.notConfirmed.rawValue), "The wake at 20:59 was not set: macOS did not list it")
        XCTAssertEqual(line(.alarmRefused, reason: 99), "The wake at 20:59 was not set: it did not take the time")
        XCTAssertEqual(line(.helperSilent, alarm: nil, job: nil), "The helper gave no answer")
        XCTAssertEqual(line(.alarmCancelled), "The wake at 20:59 was taken away")
        XCTAssertEqual(line(.wokeAtAlarm), "Your Mac woke for backup.sh")
        XCTAssertEqual(line(.alarmSeenLate), "The wake at 20:59 passed while your Mac slept")
        XCTAssertEqual(line(.alarmWhileAwake), "Your Mac was awake at the wake time for backup.sh")
        XCTAssertEqual(line(.jobSeen, alarm: nil), "backup.sh started")
        XCTAssertEqual(line(.jobEnded, alarm: nil), "backup.sh ended, and your Mac can sleep")
        XCTAssertEqual(line(.endedByGrace, alarm: nil), "backup.sh was not seen to start, and your Mac can sleep")
        XCTAssertEqual(line(.endedByCap, alarm: nil), "backup.sh ran longer than the limit, and your Mac can sleep")
        XCTAssertEqual(line(.endedByStop, alarm: nil), "Stopped staying awake for backup.sh")
        XCTAssertEqual(line(.endedOnBattery, alarm: nil), "On battery, your Mac does not stay awake for backup.sh")
        XCTAssertEqual(line(.bridgeOver, alarm: nil, job: "Digest"), "The wait for Digest is over")
        XCTAssertEqual(PanelText.jobEventTime(at("2026-10-10 03:02"), now: now, calendar: calendar, locale: locale), "03:02")
        XCTAssertEqual(PanelText.jobEventTime(at("2026-10-08 03:02"), now: now, calendar: calendar, locale: locale), "Oct 8, 03:02")
    }

    // MARK: Menu

    private func input(_ decision: HoldDecision) -> PanelInput {
        var input = PanelInput(decision: decision)
        input.calendar = calendar
        input.locale = locale
        return input
    }

    private func hold(seen: Bool = false) -> JobHold {
        let fire = at("2026-10-10 12:01").timeIntervalSince1970
        return JobHold(id: "crontab:backup@1", jobID: "crontab:backup", source: .crontab, name: "backup.sh", start: fire - 60, fireAt: fire, startGrace: 240, cap: 1800, seenAt: seen ? fire + 2 : nil)
    }

    private func decide(_ jobs: [JobHold], pausedUntil: Date? = nil, readings: [AgentReading] = []) -> HoldDecision {
        HoldPolicy.decide(
            readings: readings, memory: PolicyMemory(), mode: .agentWorking, enabled: true, pausedUntil: pausedUntil, jobHolds: jobs,
            entitlement: .licensed, safety: nil, settings: DetectionSettings(), context: FrameContext(), now: now
        ).0
    }

    func testTheQuietLineWhileAnAlarmIsSet() {
        var input = input(decide([]))
        XCTAssertNil(MenuModel.state(input, now: now).wakeLine)
        input.wakeAlarm = alarm("2026-10-10 20:59", "backup")
        XCTAssertEqual(MenuModel.state(input, now: now).wakeLine, "Wakes at 20:59 for backup")
        input.wakeAlarm = alarm("2026-10-11 09:14", "backup")
        XCTAssertEqual(MenuModel.state(input, now: now).wakeLine, "Wakes tomorrow at 09:14 for backup")
        XCTAssertNil(MenuModel.state(input, now: at("2026-10-11 09:14")).wakeLine, "Not after its time")
    }

    func testTheHeadlineAndTheLineOfAJobHold() {
        XCTAssertEqual(PanelText.headline(.scheduledJob(.one("backup.sh"))).title, "Your Mac stays awake")
        XCTAssertEqual(PanelText.headline(.scheduledJob(.one("backup.sh"))).subtitle, "For the job backup.sh")
        XCTAssertEqual(PanelText.headline(.scheduledJob(.many(2))).subtitle, "For 2 scheduled jobs")
        XCTAssertEqual(PanelText.jobHold(hold(), holding: true, now: now, calendar: calendar, locale: locale), "Awake for the job at 12:01")
        XCTAssertEqual(PanelText.jobHold(hold(seen: true), holding: true, now: now, calendar: calendar, locale: locale), "Awake while the job runs")
        XCTAssertEqual(PanelText.jobHold(hold(), holding: false, now: now, calendar: calendar, locale: locale), "Asked to stay awake for a job")
        for seen in [false, true] {
            XCTAssertLessThanOrEqual(PanelText.jobHold(hold(seen: seen), holding: true, now: now, calendar: calendar, locale: Locale(identifier: "en_US")).count, 32, "It fits next to Stop")
        }
        XCTAssertEqual(PanelText.title(of: .stopJobHold(id: "x")), "Stop")
    }

    func testAJobHoldHasALineWithAWayToStopIt() {
        let state = MenuModel.state(input(decide([hold()])), now: now)
        XCTAssertEqual(state.subtitle, "For the job backup.sh")
        XCTAssertEqual(state.pose, .awake(wisps: 2))
        XCTAssertNil(state.emptyText, "The list is not empty")
        XCTAssertEqual(state.groups.count, 1)
        let group = state.groups[0]
        XCTAssertEqual(group.header.name, "backup.sh")
        XCTAssertEqual(group.header.state, .working)
        XCTAssertEqual(group.header.detail, "Awake for the job at 12:01")
        XCTAssertEqual(group.stop, .stopJobHold(id: "crontab:backup@1"))
        XCTAssertFalse(group.canToggle)
        XCTAssertEqual(group.id, MenuModel.jobRowID("crontab:backup@1"))
    }

    func testInAStopAJobHoldIsOnlyAskedFor() {
        let state = MenuModel.state(input(decide([hold()], pausedUntil: at("2026-10-10 13:00"))), now: now)
        XCTAssertEqual(state.groups.first?.header.state, .idle)
        XCTAssertEqual(state.groups.first?.header.detail, "Asked to stay awake for a job")
        XCTAssertEqual(state.groups.first?.stop, .stopJobHold(id: "crontab:backup@1"))
    }

    func testThePicturesOfTheMenuShowAJobAndAWake() {
        XCTAssertEqual(PanelFixtures.jobHold.subtitle, "For the job backup.sh")
        XCTAssertEqual(PanelFixtures.jobHold.wakeLine, "Wakes at 12:12 for com.example.report")
        XCTAssertTrue(PanelFixtures.jobHold.groups.contains { $0.stop == .stopJobHold(id: "crontab:backup@1") })
        XCTAssertEqual(PanelFixtures.wakeSet.wakeLine, "Wakes at 12:12 for backup.sh")
        XCTAssertEqual(PanelFixtures.wakeSet.title, PanelText.canSleepTitle)
    }

    /// A crontab line with a secret, from the reader to every line the
    /// user sees: the name of the command is shown and nothing else.
    func testNoLineShowsMoreOfAJobThanItsName() throws {
        let job = try XCTUnwrap(CrontabJobReader.jobs("15 3 * * * /Users/someone/clients/acme-secret/backup.sh --password hunter2secret").first)
        let fire = at("2026-10-11 03:15")
        var settings = JobSettings()
        settings.set(true, for: job.id)
        let hold = try XCTUnwrap(JobHold.open(job: settings.applied(to: [job])[0], fireAt: fire, settings: settings))
        let alarm = JobAlarm(at: fire.addingTimeInterval(-60), fireAt: fire, jobID: job.id, jobName: job.name)
        var input = input(decide([hold]))
        input.wakeAlarm = alarm
        let state = MenuModel.state(input, now: fire)
        var all = ""
        dump(state, to: &all)
        all += PanelText.jobDetail(JobRun(job: job, fireAt: fire, tooOften: false), now: now, calendar: calendar, locale: locale)
        all += status(.alarmSet(alarm)) ?? ""
        all += PanelText.wakesAt(alarm, now: now, calendar: calendar, locale: locale)
        all += PanelText.jobEvent(JobEvent(at: 0, kind: .jobSeen, job: job.name))
        all += HoldHeadline.scheduledJob(.one(hold.subject)).text
        XCTAssertTrue(all.contains("backup.sh"))
        for word in ["someone", "acme", "secret", "password", "hunter2", "clients", "--"] {
            XCTAssertFalse(all.localizedCaseInsensitiveContains(word), word)
        }
    }
}
