import XCTest

/// The job holds of the loop: when one opens and how it ends, and how a
/// job is found among the processes.
final class JobWakeHoldTests: XCTestCase {
    private typealias Row = ProcessInfoRow

    private let clock = JobTime.clock()
    private let noon = JobTime.date("2026-10-10 12:00")
    /// The alarm of the job at 21:00.
    private let alarm = JobTime.date("2026-10-10 20:59")
    private var wake = JobWake()
    private var asleep: TimeInterval = 0

    override func setUp() {
        wake = JobWake()
        asleep = 0
    }

    private func input(_ source: ScheduledJob.Source = .crontab, name: String = "backup.sh") -> JobWakeInput {
        let schedule: JobSchedule = source == .hermes
            ? .reported(ReportedSchedule(cron: JobTime.cron("0 21 * * *"))) : .cron(JobTime.cron("0 21 * * *"))
        let job = ScheduledJob(id: "\(source.rawValue):backup", source: source, name: name, schedule: schedule)
        var input = JobWakeInput(readings: [JobSourceReading(source: source, jobs: [job])])
        input.settings.wakeForJobs = true
        input.settings.set(true, for: job.id)
        return input
    }

    @discardableResult
    private func turn(_ input: JobWakeInput, _ now: Date) -> TimeInterval? {
        wake.turn(input, now: now, awake: 1000, asleep: asleep, clock: clock)
    }

    /// The alarm is set at noon, the Mac sleeps, and wakes at the alarm.
    private func wakeAtTheAlarm(_ input: JobWakeInput, file: StaticString = #filePath, line: UInt = #line) {
        guard let time = turn(input, noon) else { return XCTFail("No time was asked for", file: file, line: line) }
        wake.answered(.set(time), for: time, now: noon, awake: 1000)
        asleep += 8 * 3600
        turn(input, alarm.addingTimeInterval(2))
    }

    private var kinds: [JobEvent.Kind] { wake.memory.history.events.map(\.kind) }
    private var holdID: String { "crontab:backup@\(Int(alarm.timeIntervalSince1970) + 60)" }

    // MARK: Open

    func testAHoldOpensWhenTheAlarmHasCome() {
        let time = turn(input(), noon)!
        wake.answered(.set(time), for: time, now: noon, awake: 1000)
        turn(input(), alarm.addingTimeInterval(-1))
        XCTAssertEqual(wake.holds, [], "Not before the alarm")
        asleep += 8 * 3600
        turn(input(), alarm.addingTimeInterval(2))
        XCTAssertEqual(wake.holds.map(\.id), [holdID])
        let hold = wake.holds[0]
        XCTAssertEqual(hold.startedAt, alarm)
        XCTAssertEqual(hold.name, "backup.sh")
        XCTAssertEqual(hold.state(now: alarm.addingTimeInterval(2)), .waiting)
        XCTAssertEqual(wake.nextTurn, alarm.addingTimeInterval(60 + 240), "The end of the hold, the next alarm is a day away")
        XCTAssertEqual(wake.watched.map(\.id), [holdID])
    }

    func testNoHoldWithoutAnAlarmThatTheHelperConfirmed() {
        turn(input(), noon)
        asleep += 8 * 3600
        turn(input(), alarm.addingTimeInterval(2))
        XCTAssertEqual(wake.holds, [])
    }

    func testNoHoldForAJobThatWasSwitchedOffMeanwhile() {
        var off = input()
        let time = turn(off, noon)!
        wake.answered(.set(time), for: time, now: noon, awake: 1000)
        off.settings.set(false, for: "crontab:backup")
        turn(off, alarm)
        XCTAssertEqual(wake.holds, [])
    }

    // MARK: End

    func testItEndsWhenTheJobWasSeenAndIsGone() {
        wakeAtTheAlarm(input())
        wake.observe([holdID: false], now: alarm.addingTimeInterval(30))
        XCTAssertEqual(wake.holds.count, 1, "Not seen yet")
        wake.observe([holdID: true], now: alarm.addingTimeInterval(62))
        XCTAssertEqual(wake.holds.first?.state(now: alarm.addingTimeInterval(62)), .running)
        wake.observe([holdID: true], now: alarm.addingTimeInterval(400))
        XCTAssertEqual(wake.holds.count, 1, "A job that runs holds past the start grace")
        wake.observe([holdID: false], now: alarm.addingTimeInterval(500))
        XCTAssertEqual(wake.holds, [])
        XCTAssertEqual(kinds, [.alarmSet, .wokeAtAlarm, .jobSeen, .jobEnded])
    }

    func testItEndsAtTheStartGraceWhenTheJobWasNeverSeen() {
        wakeAtTheAlarm(input())
        turn(input(), alarm.addingTimeInterval(60 + 239))
        XCTAssertEqual(wake.holds.count, 1)
        turn(input(), alarm.addingTimeInterval(60 + 240))
        XCTAssertEqual(wake.holds, [])
        XCTAssertEqual(kinds.last, .endedByGrace)
    }

    func testAHoldThatCouldNotBeLookedForEndsAtTheStartGrace() {
        wakeAtTheAlarm(input())
        wake.observe([:], now: alarm.addingTimeInterval(100))
        XCTAssertEqual(wake.holds.first?.seenAt, nil)
        turn(input(), alarm.addingTimeInterval(60 + 240))
        XCTAssertEqual(kinds.last, .endedByGrace)
    }

    func testItEndsAtTheCapWhileTheJobStillRuns() {
        wakeAtTheAlarm(input())
        wake.observe([holdID: true], now: alarm.addingTimeInterval(70))
        turn(input(), alarm.addingTimeInterval(1799))
        XCTAssertEqual(wake.holds.count, 1)
        turn(input(), alarm.addingTimeInterval(1800))
        XCTAssertEqual(wake.holds, [])
        XCTAssertEqual(kinds.suffix(2), [.jobSeen, .endedByCap])
    }

    func testStopEndsIt() {
        wakeAtTheAlarm(input())
        wake.stop(holdID: "no such hold", now: alarm)
        XCTAssertEqual(wake.holds.count, 1)
        wake.stop(holdID: holdID, now: alarm.addingTimeInterval(5))
        XCTAssertEqual(wake.holds, [])
        XCTAssertEqual(kinds.last, .endedByStop)
        XCTAssertEqual(wake.memory.history.events.last?.job, "backup.sh")
    }

    func testTheSwitchOfTheJobAndOfTheFeatureEndIt() {
        let changes: [(inout JobWakeInput) -> Void] = [{ $0.settings.wakeForJobs = false }, { $0.settings.set(false, for: "crontab:backup") }]
        for change in changes {
            wake = JobWake()
            asleep = 0
            wakeAtTheAlarm(input())
            var changed = input()
            change(&changed)
            turn(changed, alarm.addingTimeInterval(10))
            XCTAssertEqual(wake.holds, [])
            XCTAssertEqual(kinds.last, .endedByStop)
        }
    }

    func testTheHoldOfAnAgentJobIsABridgeThatNobodyWatches() {
        wakeAtTheAlarm(input(.hermes, name: "Digest"))
        XCTAssertEqual(wake.holds.count, 1)
        XCTAssertEqual(wake.watched, [])
        let id = wake.holds[0].id
        wake.observe([id: true], now: alarm.addingTimeInterval(70))
        XCTAssertNil(wake.holds[0].seenAt)
        turn(input(.hermes, name: "Digest"), alarm.addingTimeInterval(60 + 299))
        XCTAssertEqual(wake.holds.count, 1)
        turn(input(.hermes, name: "Digest"), alarm.addingTimeInterval(60 + 300))
        XCTAssertEqual(wake.holds, [])
        XCTAssertEqual(kinds.last, .bridgeOver)
    }

    // MARK: Processes

    private func hold(_ source: ScheduledJob.Source, id: String, name: String) -> JobHold {
        JobHold(id: "\(id)@1", jobID: id, source: source, name: name, start: 1000, fireAt: 1060, startGrace: 240, cap: 1800)
    }

    func testWhatIsLookedFor() {
        XCTAssertEqual(JobRunMatch.launchdLabel(of: hold(.launchd, id: "launchd:com.example.backup", name: "com.example.backup")), "com.example.backup")
        XCTAssertNil(JobRunMatch.launchdLabel(of: hold(.launchd, id: "launchd:-x", name: "-x")), "It would read as an option")
        XCTAssertNil(JobRunMatch.launchdLabel(of: hold(.crontab, id: "crontab:a", name: "a")))
        XCTAssertEqual(JobRunMatch.cronName(of: hold(.crontab, id: "crontab:a", name: "backup.sh")), "backup.sh")
        XCTAssertNil(JobRunMatch.cronName(of: hold(.crontab, id: "crontab:a", name: "cron job 3")), "Any process of cron could be it")
        XCTAssertNil(JobRunMatch.cronName(of: hold(.hermes, id: "hermes:a", name: "Digest")))
    }

    func testLaunchdListsAPidWhileTheJobRuns() {
        let running = "{\n\t\"LimitLoadToSessionType\" = \"Aqua\";\n\t\"Label\" = \"com.example.backup\";\n\t\"LastExitStatus\" = 0;\n\t\"PID\" = 4242;\n\t\"Program\" = \"/usr/bin/true\";\n};\n"
        XCTAssertTrue(JobRunMatch.launchdRuns(listOutput: running))
        XCTAssertFalse(JobRunMatch.launchdRuns(listOutput: running.replacingOccurrences(of: "\t\"PID\" = 4242;\n", with: "")))
        XCTAssertFalse(JobRunMatch.launchdRuns(listOutput: "\"ProgramArguments\" = (\n\t\"PID = 12\";\n);"))
        XCTAssertFalse(JobRunMatch.launchdRuns(listOutput: ""))
    }

    func testACronJobIsAProcessBelowCronWithTheNameThatStartedAfterTheAlarm() {
        let cron = Row.fixture(300, ppid: 1, start: 10, path: "/usr/sbin/cron")
        let child = Row.fixture(900, ppid: 300, start: 1061, path: "/usr/sbin/cron")
        let shell = Row.fixture(901, ppid: 900, start: 1061, path: "/bin/sh", args: ["/bin/sh", "-c", "/Users/someone/bin/backup.sh --key sk-live-abc"])
        let script = Row.fixture(902, ppid: 901, start: 1062, path: "/bin/bash", args: ["/bin/bash", "/Users/someone/bin/backup.sh", "--key", "sk-live-abc"])
        XCTAssertTrue(JobRunMatch.cronJobRuns(name: "backup.sh", since: 1000, rows: [cron, child, shell]))
        XCTAssertTrue(JobRunMatch.cronJobRuns(name: "backup.sh", since: 1000, rows: [cron, child, shell, script]))
        XCTAssertFalse(JobRunMatch.cronJobRuns(name: "backup.sh", since: 1000, rows: [cron, child]), "Gone")
        XCTAssertFalse(JobRunMatch.cronJobRuns(name: "other.sh", since: 1000, rows: [cron, child, shell, script]))
        XCTAssertFalse(JobRunMatch.cronJobRuns(name: "backup.sh", since: 2000, rows: [cron, child, shell, script]), "A run from before the alarm")
        let mine = Row.fixture(950, ppid: 700, start: 1062, path: "/Users/someone/bin/backup.sh")
        let terminal = Row.fixture(700, ppid: 1, start: 20, path: "/bin/zsh")
        XCTAssertFalse(JobRunMatch.cronJobRuns(name: "backup.sh", since: 1000, rows: [cron, terminal, mine]), "Started by hand, not by cron")
        let binary = Row.fixture(903, ppid: 900, start: 1061, path: "/usr/local/bin/poll")
        XCTAssertTrue(JobRunMatch.cronJobRuns(name: "poll", since: 1000, rows: [cron, child, binary]))
        XCTAssertFalse(JobRunMatch.cronJobRuns(name: "cron", since: 1000, rows: [cron, child]), "The process of cron itself is no job")
    }

    /// The real probe, with a script in the place of launchctl and rows
    /// of its own. Nothing of this Mac is asked.
    func testTheProbeAsksLaunchdAndTheProcessTable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("caffeinagent-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("launchctl.sh")
        let body = "#!/bin/sh\n[ \"$1\" = list ] || exit 9\ncase \"$2\" in\ncom.example.runs) echo '\t\"PID\" = 77;' ;;\ncom.example.idle) echo '\t\"Label\" = \"x\";' ;;\n*) exit 113 ;;\nesac\n"
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let cron = Row.fixture(300, ppid: 1, start: 10, path: "/usr/sbin/cron")
        let job = Row.fixture(901, ppid: 300, start: 1061, path: "/bin/sh", args: ["/bin/sh", "-c", "backup.sh"])
        let probe = SystemJobRunProbe(launchctl: script, rows: { [cron, job] })
        let holds = [
            hold(.launchd, id: "launchd:com.example.runs", name: "com.example.runs"),
            hold(.launchd, id: "launchd:com.example.idle", name: "com.example.idle"),
            hold(.launchd, id: "launchd:com.example.unknown", name: "com.example.unknown"),
            hold(.crontab, id: "crontab:a", name: "backup.sh"),
            hold(.crontab, id: "crontab:b", name: "cron job 2"),
            hold(.hermes, id: "hermes:c", name: "Digest"),
        ]
        XCTAssertEqual(probe.look(holds), [
            "launchd:com.example.runs@1": true, "launchd:com.example.idle@1": false, "launchd:com.example.unknown@1": false,
            "crontab:a@1": true,
        ])
        let blind = SystemJobRunProbe(launchctl: folder.appendingPathComponent("none"), rows: { nil })
        XCTAssertEqual(blind.look(holds), [:], "What cannot be looked for is left to the grace and the cap")
    }
}
