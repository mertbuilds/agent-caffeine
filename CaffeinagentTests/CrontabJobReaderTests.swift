import XCTest

final class CrontabJobReaderTests: XCTestCase {
    private static let crontab = [
        "# Backups, each night",
        "SHELL=/bin/zsh",
        "MAILTO = someone@example.com",
        "API_TOKEN=sk-live-envsecret",
        "",
        "   # 0 1 * * * /usr/bin/old",
        "15 3 * * * /Users/someone/clients/acme-secret/backup.sh --password hunter2secret >> /tmp/backup.log 2>&1",
        "0\t9\t*\t*\tMON-FRI\tcurl -H \"Authorization: Bearer sk-live-headersecret\" https://example.com/hook",
        "@daily ~/bin/report --to boss@example.com",
        "*/5 * * * * TOKEN=sk-live-inlinesecret /usr/local/bin/poll",
        "@reboot /usr/local/bin/at-start",
        "0 0 12 * * ? /usr/bin/quartz",
        "*/10 * * * * * /usr/bin/seconds",
        "0 0 1 1 * 2027 /usr/bin/year",
        "61 * * * * /usr/bin/wrong",
        "30 4 1 * * \"/Applications/My Tool.app/Contents/MacOS/tool\" run",
        "0 6 * * * w",
        "0 7 * * *",
    ].joined(separator: "\n")

    func testOnlyTheJobLinesAreTaken() {
        let jobs = CrontabJobReader.jobs(Self.crontab)
        XCTAssertEqual(jobs.map(\.name), ["backup.sh", "curl", "report", "cron job 4", "cron job 5", "w"])
        XCTAssertEqual(jobs.map(\.schedule), [
            .cron(JobTime.cron("15 3 * * *")), .cron(JobTime.cron("0 9 * * 1-5")), .cron(JobTime.cron("0 0 * * *")),
            .cron(JobTime.cron("*/5 * * * *")), .cron(JobTime.cron("30 4 1 * *")), .cron(JobTime.cron("0 6 * * *")),
        ])
        XCTAssertTrue(jobs.allSatisfy { $0.source == .crontab && !$0.enabled }, "Nothing is adopted by itself")
        XCTAssertEqual(jobs[0].id, "crontab:15 3 * * *:backup.sh")
    }

    func testAJobHoldsOnlyItsTimesAndTheNameOfItsCommand() {
        let jobs = CrontabJobReader.jobs(Self.crontab)
        XCTAssertEqual(jobs.count, 6)
        JobPrivacy.check(jobs, neverHolds: [
            "secret", "hunter2", "password", "sk-live", "Bearer", "Authorization", "example.com", "someone", "acme", "clients", "/tmp",
            "boss", "--", "TOKEN", "poll", "My Tool", "Applications", "zsh",
        ])
    }

    func testTheNameIsTheFirstWordWithoutItsFolder() {
        func name(_ command: String) -> String { CrontabJobReader.name(ofCommand: Substring(command), number: 3) }
        XCTAssertEqual(name("/opt/homebrew/bin/ffmpeg -i in.mov out.mp4"), "ffmpeg")
        XCTAssertEqual(name("/Users/someone/private-folder/run.sh"), "run.sh", "A path in the home folder is cut to its last part")
        XCTAssertEqual(name("~/bin/sync_all-2.sh"), "sync_all-2.sh")
        XCTAssertEqual(name("/usr/bin/"), "bin")
        XCTAssertEqual(name("python3"), "python3")
        for command in [
            "KEY=abc123 /usr/bin/run", "\"/path with space/run\" x", "'/usr/bin/run'", "$HOME/bin/run", "`which run`", "(cd /x; run)",
            "run;rm", "run|tee", "run>out", "~", "12345", "https://user:pass@example.com/x",
            "/usr/bin/" + String(repeating: "a", count: 41), "rün",
        ] {
            XCTAssertEqual(name(command), "cron job 3", command)
        }
    }

    func testTwoLinesWithTheSameTimesAndNameHaveTwoIds() {
        let jobs = CrontabJobReader.jobs("0 3 * * * python3 a.py\n0 3 * * * python3 b.py\n0 4 * * * python3 a.py\n0 3 * * * /usr/bin/python3 c.py")
        XCTAssertEqual(jobs.map(\.id), ["crontab:0 3 * * *:python3", "crontab:0 3 * * *:python3#2", "crontab:0 4 * * *:python3", "crontab:0 3 * * *:python3#3"])
        XCTAssertEqual(Set(jobs.map(\.id)).count, 4)
    }

    /// The id of such a line holds its place among the lines that look
    /// the same, or its count among all lines. A line that is added or
    /// removed would move a switch to another command. So these lines
    /// are listed and get no switch.
    func testALineThatCannotBeToldApartGetsNoSwitch() {
        let text = "0 3 * * * python3 a.py\n0 3 * * * python3 b.py\n0 4 * * * python3 a.py\n*/40 * * * * TOKEN=abc run\n0 5 * * * /usr/bin/backup"
        let jobs = CrontabJobReader.jobs(text)
        XCTAssertEqual(jobs.map(\.name), ["python3", "python3", "python3", "cron job 4", "backup"])
        XCTAssertEqual(jobs.map(\.noSwitch), [.sameLines, .sameLines, nil, .noPlainName, nil])
        XCTAssertEqual(Set(jobs.map(\.id)).count, 5, "Each still has an id of its own for the list")

        // The switches of an earlier version of the list, all on.
        var settings = JobSettings()
        for job in jobs { settings.set(true, for: job.id) }
        XCTAssertEqual(settings.applied(to: jobs).map(\.enabled), [false, false, true, false, true])
        // Their switches are forgotten, so none comes back on another line.
        settings = settings.withoutSwitches(ofUnclear: jobs)
        XCTAssertEqual(settings.jobSwitches.keys.sorted(), ["crontab:0 4 * * *:python3", "crontab:0 5 * * *:backup"])
        // The first line is removed: b.py has the id that a.py had.
        let after = CrontabJobReader.jobs(text.components(separatedBy: "\n").dropFirst().joined(separator: "\n"))
        XCTAssertEqual(after.map(\.noSwitch), [nil, nil, .noPlainName, nil])
        XCTAssertEqual(after.first?.id, jobs.first?.id)
        XCTAssertEqual(settings.applied(to: after).map(\.enabled), [false, true, false, true], "b.py does not get the switch that a.py had")
        XCTAssertEqual(settings.withoutSwitches(ofUnclear: after.filter { $0.noSwitch == nil }), settings, "Nothing else is forgotten")
    }

    func testTheLineOfAJobWithNoSwitchSaysWhy() {
        let jobs = CrontabJobReader.jobs("0 3 * * * python3 a.py\n0 3 * * * python3 b.py\n0 6 * * * TOKEN=abc run")
        let lines = jobs.map { PanelText.jobDetail(JobRun(job: $0, fireAt: nil, tooOften: false), now: Date(timeIntervalSince1970: 0)) }
        XCTAssertEqual(lines, [
            "crontab · Two lines look the same, so Agent Caffeine cannot tell them apart",
            "crontab · Two lines look the same, so Agent Caffeine cannot tell them apart",
            "crontab · The command has no plain name, so Agent Caffeine cannot tell this line apart",
        ])
    }

    func testAJobWithNoSwitchGetsNoAlarm() {
        var jobs = CrontabJobReader.jobs("0 3 * * * python3 a.py\n0 3 * * * python3 b.py")
        for index in jobs.indices { jobs[index].enabled = true }
        var settings = JobSettings()
        settings.wakeForJobs = true
        let plan = JobPlanner.plan(jobs: jobs, settings: settings, context: JobPlanContext(), now: JobTime.date("2026-10-10 12:00"), clock: JobTime.clock())
        XCTAssertNil(plan.alarm, "Also when a caller says it is on")
        XCTAssertEqual(plan.noAlarm, .noJobSwitchedOn)
        XCTAssertEqual(plan.nextRuns.count, 2, "Both are listed")
    }

    func testTheIdStaysWhenOtherLinesChange() {
        let before = CrontabJobReader.jobs("15 3 * * * /usr/bin/backup --key one")
        let after = CrontabJobReader.jobs("# new\nPATH=/bin\n0 1 * * * /usr/bin/other\n15  3 * * *   /usr/bin/backup --key two")
        XCTAssertEqual(after.last?.id, before.first?.id)
    }

    func testLinesWithSixTimeFieldsAreRefused() {
        for word in ["*", "*/5", "1-5", "2027", "?", "MON", "mon-fri", "JAN,FEB", "L", "15W", "5#3"] {
            XCTAssertTrue(CrontabJobReader.looksLikeATimeField(Substring(word)), word)
            XCTAssertEqual(CrontabJobReader.jobs("0 0 1 * * \(word) /usr/bin/run"), [], word)
        }
        for word in ["w", "7z", "/usr/bin/run", "run", "2to3", "-", "monday"] {
            XCTAssertFalse(CrontabJobReader.looksLikeATimeField(Substring(word)), word)
        }
    }

    func testEndsOfLines() {
        XCTAssertEqual(CrontabJobReader.jobs("0 3 * * * a\r\n0 4 * * * b\r\n").map(\.name), ["a", "b"])
        XCTAssertEqual(CrontabJobReader.jobs(""), [])
        XCTAssertEqual(CrontabJobReader.jobs("\n\n# nothing\n"), [])
    }

    // MARK: The source

    func testTheStatusOfTheSource() {
        let access = FixtureJobAccess()
        XCTAssertEqual(CrontabJobReader().read(access), JobSourceReading(source: .crontab, jobs: []))
        XCTAssertEqual(CrontabJobReader().read(access).status, JobSourceStatus.none, "No crontab is no failure")

        access.crontabResult = .found("# only a comment\n")
        XCTAssertEqual(CrontabJobReader().read(access).status, JobSourceStatus.none)

        access.crontabResult = .found(Self.crontab)
        let reading = CrontabJobReader().read(access)
        XCTAssertEqual(reading.status, .ok)
        XCTAssertEqual(reading.jobs.count, 6)

        access.crontabResult = .failed("crontab ended with code 2")
        XCTAssertEqual(CrontabJobReader().read(access).status, .unreadable("crontab ended with code 2"))
        XCTAssertEqual(CrontabJobReader().read(access).jobs, [])
    }

    func testWhatARunOfTheCommandMeans() {
        guard case .found("0 3 * * * a\n") = CrontabJobReader.output(status: 0, stdout: "0 3 * * * a\n", stderr: "") else { return XCTFail() }
        guard case .missing = CrontabJobReader.output(status: 1, stdout: "", stderr: "crontab: no crontab for someone\n") else { return XCTFail() }
        guard case .failed(let reason) = CrontabJobReader.output(status: 2, stdout: "", stderr: "crontab: secret detail") else { return XCTFail() }
        XCTAssertEqual(reason, "crontab ended with code 2", "The error output is not passed on")
    }
}
