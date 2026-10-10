import XCTest

/// Stands in for the helper: it remembers every time it was asked for
/// and sets no alarm anywhere.
@MainActor
private final class FakeSender: WakeAlarmSending {
    /// What was asked, in order. "now" marks a call that blocks.
    var asked: [String] = []
    /// Nil sets what is asked for.
    var result: WakeAlarmResult?

    /// Runs at every call that does not block, before the answer.
    var onAsk: (() -> Void)?

    private func answer(_ time: TimeInterval) -> WakeAlarmResult {
        result ?? (time > 0 ? .set(time) : .cancelled)
    }

    func wakeAlarm(at time: TimeInterval) async -> WakeAlarmResult {
        asked.append("\(Int(time))")
        onAsk?()
        return answer(time)
    }

    func wakeAlarmNow(at time: TimeInterval, timeout: TimeInterval) -> WakeAlarmResult {
        asked.append("now \(Int(time))")
        return answer(time)
    }
}

private final class FakeProbe: JobRunProbing, @unchecked Sendable {
    var answers: [String: Bool] = [:]
    var looks = 0

    func running(_ holds: [JobHold]) async -> [String: Bool] {
        looks += 1
        return answers.filter { entry in holds.contains { $0.id == entry.key } }
    }
}

/// The loop as the app runs it, with a helper, a clock and processes
/// that exist only in the test.
@MainActor
final class JobWakeLoopTests: XCTestCase {
    private var sender: FakeSender!
    private var probe: FakeProbe!
    private var defaults: TestDefaults!
    private var now = JobTime.date("2026-10-10 12:00")
    private var awake: TimeInterval = 1000
    private var asleep: TimeInterval = 0
    private var loop: JobWakeLoop!

    private let alarm = JobTime.date("2026-10-10 20:59")
    private var alarmTime: Int { Int(alarm.timeIntervalSince1970) }
    private var nextAlarmTime: Int { alarmTime + 86_400 }
    private var holdID: String { "crontab:backup@\(alarmTime + 60)" }

    override func setUp() async throws {
        sender = FakeSender()
        probe = FakeProbe()
        defaults = TestDefaults()
        now = JobTime.date("2026-10-10 12:00")
        awake = 1000
        asleep = 0
        loop = makeLoop()
    }

    private func makeLoop() -> JobWakeLoop {
        JobWakeLoop(
            sender: sender, probe: probe, defaults: defaults,
            clocks: AwakeClock(awake: { [unowned self] in self.awake }, asleep: { [unowned self] in self.asleep }),
            now: { [unowned self] in self.now }, jobClock: { JobTime.clock() }
        )
    }

    private var input: JobWakeInput {
        let job = ScheduledJob(id: "crontab:backup", source: .crontab, name: "backup", schedule: .cron(JobTime.cron("0 21 * * *")))
        var input = JobWakeInput(readings: [
            JobSourceReading(source: .crontab, jobs: [job]), JobSourceReading(source: .hermes, unreadable: "jobs.json is no JSON"),
        ])
        input.settings.wakeForJobs = true
        input.settings.set(true, for: job.id)
        return input
    }

    /// Until the call and the look that are under way are over.
    private func settle() async {
        for _ in 0..<5 {
            await loop.sending?.value
            await loop.looking?.value
        }
    }

    /// The Mac sleeps until the alarm and the loop runs two seconds after it.
    private func wakeAtTheAlarm() async {
        asleep += 8 * 3600
        now = alarm.addingTimeInterval(2)
        loop.run()
        await settle()
    }

    func testAChangeOfTheInputSendsTheAlarmAndShowsIt() async {
        var changes = 0
        loop.onChange = { changes += 1 }
        loop.run(input)
        XCTAssertEqual(loop.view.status, .asking)
        await settle()
        XCTAssertEqual(sender.asked, ["\(alarmTime)"])
        XCTAssertEqual(loop.view.alarm?.at, alarm)
        XCTAssertEqual(loop.view.alarm?.jobName, "backup")
        XCTAssertEqual(loop.view.status, .alarmSet(loop.view.alarm!))
        XCTAssertEqual(loop.view.runs.map(\.job.name), ["backup"])
        XCTAssertEqual(loop.view.sources, [.crontab: .ok, .hermes: .unreadable("jobs.json is no JSON")])
        XCTAssertEqual(loop.view.history.map(\.kind), [.alarmSet])
        XCTAssertEqual(loop.nextTurn, alarm)
        XCTAssertGreaterThan(changes, 0)
        loop.run(input)
        await settle()
        XCTAssertEqual(sender.asked.count, 1, "The same input and the same time bring no call")
    }

    func testTheLeaseIsRenewedWhileTheAlarmIsWanted() async {
        loop.run(input)
        await settle()
        awake += JobWake.renewEvery
        loop.run()
        await settle()
        XCTAssertEqual(sender.asked, ["\(alarmTime)", "\(alarmTime)"])
        loop.run()
        await settle()
        XCTAssertEqual(sender.asked.count, 2)
    }

    /// The helper is root, so one run never brings a row of calls,
    /// whatever the rules of `JobWake` say. Here each call moves the
    /// clock a day on, so every answer is followed by a new time.
    func testOneRunBringsNoMoreThanAFewCalls() async {
        sender.onAsk = { [unowned self] in
            if self.sender.asked.count <= 20 { self.now = self.now.addingTimeInterval(86_400) }
        }
        loop.run(input)
        for _ in 0..<60 { await loop.sending?.value }
        XCTAssertEqual(sender.asked.count, JobWakeLoop.callsPerRun)
        XCTAssertLessThanOrEqual(JobWakeLoop.callsPerRun, 3)
        XCTAssertEqual(Set(sender.asked).count, JobWakeLoop.callsPerRun, "A new time each")
        loop.run()
        for _ in 0..<60 { await loop.sending?.value }
        XCTAssertEqual(sender.asked.count, 2 * JobWakeLoop.callsPerRun, "The next run goes on")
    }

    func testARenewalThatIsRefusedBringsOneCallAndNoLoop() async {
        loop.run(input)
        await settle()
        awake += JobWake.renewEvery
        sender.result = .refused(.tooOften)
        for second in 0..<60 {
            awake += second == 0 ? 0 : 1
            loop.run()
            for _ in 0..<20 { await loop.sending?.value }
        }
        XCTAssertEqual(sender.asked, ["\(alarmTime)", "\(alarmTime)"], "The first time and one renewal")
    }

    func testSwitchingTheFeatureOffCancelsAndASilentHelperIsAStatus() async {
        loop.run(input)
        await settle()
        var off = input
        off.settings.wakeForJobs = false
        loop.run(off)
        await settle()
        XCTAssertEqual(sender.asked, ["\(alarmTime)", "0"])
        XCTAssertEqual(loop.view.status, .off)
        XCTAssertNil(loop.view.alarm)
        XCTAssertEqual(loop.view.history.map(\.kind), [.alarmCancelled, .alarmSet], "The newest first")
        sender.result = .helperNotAvailable
        loop.run(input)
        await settle()
        XCTAssertEqual(loop.view.status, .helperSilent)
        sender.result = .refused(.tooOften)
        awake += JobWake.retryAfter
        loop.run()
        await settle()
        XCTAssertEqual(loop.view.status, .refused(.tooOften))
    }

    func testWillSleepSendsThePlanForASleepingMacBeforeItReturns() async {
        now = JobTime.date("2026-10-10 20:40")
        loop.run(input)
        await settle()
        XCTAssertEqual(sender.asked, ["\(nextAlarmTime)"], "Awake, the job in 20 minutes needs no alarm")
        loop.willSleep()
        XCTAssertEqual(sender.asked, ["\(nextAlarmTime)", "now \(alarmTime)"])
        XCTAssertEqual(loop.view.alarm?.at, alarm, "No await in between")
        loop.run()
        await settle()
        XCTAssertEqual(sender.asked.count, 2, "A sample before the sleep changes nothing")
        loop.wokeInFull()
        await settle()
        XCTAssertEqual(sender.asked.count, 2, "Awake in full again, and the alarm that is set stays")
    }

    func testAHoldOpensAtTheAlarmAndEndsWhenTheJobIsGone() async {
        var changes = 0
        loop.run(input)
        await settle()
        loop.onChange = { changes += 1 }
        await wakeAtTheAlarm()
        XCTAssertEqual(loop.holds.map(\.id), [holdID])
        XCTAssertGreaterThan(changes, 0)
        XCTAssertEqual(probe.looks, 1)
        XCTAssertEqual(sender.asked.last, "\(nextAlarmTime)", "The next alarm is set at once")
        loop.run()
        await settle()
        XCTAssertEqual(probe.looks, 1, "The processes are not looked at with every sample")
        probe.answers = [holdID: true]
        awake += JobWakeLoop.probeEvery
        now = alarm.addingTimeInterval(65)
        loop.run()
        await settle()
        XCTAssertNotNil(loop.holds.first?.seenAt)
        probe.answers = [holdID: false]
        awake += JobWakeLoop.probeEvery
        now = alarm.addingTimeInterval(200)
        loop.run()
        await settle()
        XCTAssertEqual(loop.holds, [])
        XCTAssertEqual(loop.view.history.map(\.kind), [.jobEnded, .jobSeen, .alarmSet, .wokeAtAlarm, .alarmSet])
    }

    func testStopEndsTheHold() async {
        loop.run(input)
        await settle()
        await wakeAtTheAlarm()
        loop.stopHold(id: holdID)
        XCTAssertEqual(loop.holds, [])
        XCTAssertEqual(loop.view.history.first?.kind, .endedByStop)
    }

    func testQuitCancelsOnceAndOnlyWithAnAlarm() async {
        loop.cancelNow()
        XCTAssertEqual(sender.asked, [])
        loop.run(input)
        await settle()
        loop.cancelNow()
        XCTAssertEqual(sender.asked, ["\(alarmTime)", "now 0"])
        XCTAssertNil(loop.view.alarm)
        loop.cancelNow()
        XCTAssertEqual(sender.asked.count, 2)
    }

    func testAfterTheHelperWasReplacedTheAlarmIsSetAgain() async {
        loop.run(input)
        await settle()
        loop.helperReplaced()
        await settle()
        XCTAssertEqual(sender.asked, ["\(alarmTime)", "\(alarmTime)"])
        XCTAssertEqual(loop.view.alarm?.at, alarm)
    }

    func testTheMemoryLastsOverARestartOfTheApp() async {
        loop.run(input)
        await settle()
        await wakeAtTheAlarm()
        let memory = JobWakeMemoryStore.load(from: defaults)
        XCTAssertEqual(memory.ledger, [alarm.timeIntervalSince1970])
        XCTAssertEqual(memory.owedAlarm, TimeInterval(nextAlarmTime))
        sender.asked = []
        loop = makeLoop()
        XCTAssertEqual(loop.view.history, [], "Nothing is shown before the first turn")
        loop.run()
        await settle()
        XCTAssertEqual(sender.asked, ["0"], "The feature is off in the new input, and the alarm of the run before is taken away")
        XCTAssertEqual(loop.view.history.map(\.kind), [.alarmCancelled, .alarmSet, .wokeAtAlarm, .alarmSet])
    }

    /// A normal edit of the crontab: a second line with the same times
    /// and the same command name. The line that was on has no switch any
    /// more, and its stored switch goes. That is said, in the history
    /// and in Settings, and not done in silence.
    func testASwitchThatWasOnAndGoesOffByItselfIsSaid() async throws {
        let before = CrontabJobReader.jobs("0 21 * * * /Users/someone/bin/backup.sh --key hunter2\n0 4 * * * sync")
        var settings = JobSettings()
        settings.wakeForJobs = true
        settings.set(true, for: try XCTUnwrap(before.first?.id))
        XCTAssertEqual(loop.forgetSwitches(ofUnclear: before, in: settings), settings, "Nothing to forget")
        XCTAssertEqual(loop.view.lostSwitches, [])
        XCTAssertEqual(loop.view.history, [])

        let after = CrontabJobReader.jobs("0 21 * * * /Users/someone/bin/backup.sh --key hunter2\n0 4 * * * sync\n0 21 * * * backup.sh --other")
        XCTAssertEqual(after.map(\.noSwitch), [.sameLines, nil, .sameLines])
        var changes = 0
        loop.onChange = { changes += 1 }
        let kept = loop.forgetSwitches(ofUnclear: after, in: settings)
        XCTAssertEqual(kept.jobSwitches, [:], "The switch is forgotten")
        XCTAssertEqual(loop.view.lostSwitches, ["backup.sh"])
        XCTAssertEqual(loop.view.history.map(\.kind), [.switchLost])
        XCTAssertEqual(loop.view.history.first?.job, "backup.sh")
        XCTAssertEqual(loop.view.history.first?.at, now.timeIntervalSince1970)
        XCTAssertEqual(PanelText.jobEvent(loop.view.history[0]), "backup.sh was switched off: two lines of the crontab look the same now")
        XCTAssertEqual(changes, 1, "Settings is told")
        let stored = String(decoding: try XCTUnwrap(defaults.data(forKey: JobWakeMemoryStore.key)), as: UTF8.self)
        XCTAssertTrue(stored.contains("switchLost"), "The history is saved")
        for word in ["someone", "hunter2", "--", "other"] { XCTAssertFalse(stored.contains(word), word) }

        XCTAssertEqual(loop.forgetSwitches(ofUnclear: after, in: kept), kept)
        XCTAssertEqual(loop.view.history.count, 1, "Once, and not at every reading")
        loop.run(JobWakeInput(readings: [JobSourceReading(source: .crontab, jobs: after)], settings: kept))
        await settle()
        XCTAssertEqual(loop.view.lostSwitches, ["backup.sh"], "It stays until the user closes it")
        loop.closeSwitchNotice()
        XCTAssertEqual(loop.view.lostSwitches, [])
        XCTAssertEqual(loop.view.history.map(\.kind), [.switchLost], "The history keeps it")
    }

    func testASwitchThatWasOffGoesWithNoWord() {
        let jobs = CrontabJobReader.jobs("0 21 * * * backup.sh a\n0 21 * * * backup.sh b\n0 6 * * * TOKEN=abc run")
        var settings = JobSettings()
        XCTAssertEqual(settings.switchesLost(toUnclear: jobs), [])
        // Of an earlier version of the list: a line with no plain name never had a switch the user saw.
        settings.set(true, for: jobs[2].id)
        XCTAssertEqual(settings.switchesLost(toUnclear: jobs), [])
        XCTAssertEqual(loop.forgetSwitches(ofUnclear: jobs, in: settings).jobSwitches, [:])
        XCTAssertEqual(loop.view.history, [])
        settings.set(true, for: jobs[0].id)
        XCTAssertEqual(settings.switchesLost(toUnclear: jobs).map(\.name), ["backup.sh"])
        XCTAssertEqual(settings.withoutSwitches(ofUnclear: jobs).switchesLost(toUnclear: jobs), [])
    }

    /// The store, the log lines and the view hold the short name of a
    /// job and nothing else of it.
    func testNothingOfACommandLineIsKept() async throws {
        let line = "15 3 * * * /Users/someone/clients/acme-secret/backup.sh --password hunter2secret >> /tmp/private.log"
        var input = JobWakeInput(readings: [JobSourceReading(source: .crontab, jobs: CrontabJobReader.jobs(line))])
        input.settings.wakeForJobs = true
        input.settings.set(true, for: try XCTUnwrap(input.readings[0].jobs.first?.id))
        loop.run(input)
        await settle()
        asleep += 20 * 3600
        now = JobTime.date("2026-10-11 03:14").addingTimeInterval(1)
        loop.run()
        await settle()
        XCTAssertEqual(loop.holds.map(\.name), ["backup.sh"])
        var all = ""
        dump(loop.view, to: &all)
        dump(loop.holds, to: &all)
        all += String(decoding: try XCTUnwrap(defaults.data(forKey: JobWakeMemoryStore.key)), as: UTF8.self)
        all += sender.asked.joined() + JobWakeLoop.logText(.set(1)) + JobWakeLoop.logText(.refused(.tooSoon))
        XCTAssertTrue(all.contains("backup.sh"))
        for word in ["someone", "acme", "secret", "password", "hunter2", "private", "/tmp", "clients"] {
            XCTAssertFalse(all.localizedCaseInsensitiveContains(word), word)
        }
    }
}
