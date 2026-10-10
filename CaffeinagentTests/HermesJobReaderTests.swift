import XCTest

final class HermesJobReaderTests: XCTestCase {
    private let zone = TimeZone(identifier: JobTime.istanbul)!
    private let reader = HermesJobReader(home: FixtureJobAccess.home)
    private let clock = JobTime.clock(JobTime.istanbul)

    private func at(_ text: String, _ zone: String = JobTime.utc) -> Date { JobTime.date(text, zone) }

    private func jobs(_ json: String) -> [ScheduledJob] {
        HermesJobReader.jobs(Data(json.utf8), timeZone: zone).jobs
    }

    private func reported(_ job: ScheduledJob?, file: StaticString = #filePath, line: UInt = #line) -> ReportedSchedule {
        guard case .reported(let schedule)? = job?.schedule else {
            XCTFail("No reported schedule", file: file, line: line)
            return ReportedSchedule()
        }
        return schedule
    }

    /// As Hermes writes it, with fields that are never read.
    private static let file = #"""
    {
      "version": 3,
      "jobs": [
        {
          "id": "a1b2c3", "name": "Morning briefing", "enabled": true, "state": "scheduled",
          "prompt": "Read my inbox and send the summary to boss@example.com with token sk-live-promptsecret",
          "model": {"provider": "anthropic", "api_key": "sk-live-keysecret"},
          "schedule": {"kind": "cron", "expr": "0 9 * * 1-5", "display": "0 9 * * 1-5"},
          "schedule_display": "0 9 * * 1-5",
          "next_run_at": "2026-10-12T09:00:00.123456+03:00", "last_run_at": "2026-10-09T09:00:04+03:00", "last_status": "ok",
          "fire_claim": null, "paused_at": null, "something_new": [1, 2, 3]
        },
        {
          "id": "d4e5f6", "name": "Check the queue", "enabled": true,
          "schedule": {"kind": "interval", "minutes": 360, "display": "every 360m"},
          "next_run_at": "2026-10-10T18:00:00Z"
        },
        {"id": "off", "name": "Switched off", "enabled": false, "schedule": {"kind": "cron", "expr": "0 1 * * *"}},
        {"id": "paused1", "name": "Paused", "enabled": true, "paused_at": "2026-10-01T00:00:00Z", "schedule": {"kind": "cron", "expr": "0 2 * * *"}},
        {"id": "paused2", "name": "Paused too", "state": "paused", "schedule": {"kind": "cron", "expr": "0 2 * * *"}},
        {"id": "once", "name": "One time", "schedule": {"kind": "once"}, "next_run_at": "2026-10-11 07:30:00"},
        "not a job", 42, null,
        {"name": "No schedule"},
        {"enabled": true, "schedule": {"kind": "cron", "expr": "0 3 * * *"}}
      ]
    }
    """#

    func testTheJobsOfAFile() {
        let jobs = jobs(Self.file)
        XCTAssertEqual(jobs.map(\.id), ["hermes:a1b2c3", "hermes:d4e5f6", "hermes:once"])
        XCTAssertEqual(jobs.map(\.name), ["Morning briefing", "Check the queue", "One time"])
        XCTAssertTrue(jobs.allSatisfy { $0.source == .hermes && !$0.enabled }, "Nothing is adopted by itself")

        let briefing = reported(jobs.first)
        XCTAssertEqual(briefing.cron, JobTime.cron("0 9 * * 1-5"))
        XCTAssertEqual(briefing.nextRun, at("2026-10-12 06:00"))
        let queue = reported(jobs.dropFirst().first)
        XCTAssertNil(queue.cron)
        XCTAssertEqual(queue.everyMinutes, 360)
        XCTAssertEqual(queue.nextRun, at("2026-10-10 18:00"))
        XCTAssertEqual(reported(jobs.last).nextRun, at("2026-10-11 07:30", JobTime.istanbul), "A time with no zone is on the wall clock")
    }

    func testAJobHoldsOnlyItsTimesAndItsName() {
        let jobs = jobs(Self.file)
        XCTAssertEqual(jobs.count, 3)
        JobPrivacy.check(jobs, neverHolds: ["secret", "sk-live", "inbox", "boss", "example.com", "anthropic", "api_key", "prompt", "model", "last_status"])
    }

    func testTheNameIsOneLineOfSixtyCharacters() {
        let long = String(repeating: "Summarise everything ", count: 10)
        let jobs = jobs(#"{"jobs":[{"id":"x\ny","name":"\#(long)\nsecond line","schedule":{"expr":"0 9 * * *"}},{"id":77,"schedule":"30 6 * * *"}]}"#)
        XCTAssertEqual(jobs.first?.name.count, 60)
        XCTAssertEqual(jobs.first?.name, String(long.prefix(60)))
        XCTAssertEqual(jobs.first?.id, "hermes:x y")
        XCTAssertEqual(jobs.last?.name, "77", "The id when there is no name")
        XCTAssertEqual(reported(jobs.last).cron, JobTime.cron("30 6 * * *"))
    }

    func testTheTimeHermesWroteWinsWhileItIsAhead() {
        let job = jobs(Self.file)[0]
        // Saturday. The expression alone would say Monday 09:00 too.
        XCTAssertEqual(job.schedule.next(after: at("2026-10-10 12:00"), clock: clock), at("2026-10-12 06:00"))
        let interval = jobs(Self.file)[1]
        XCTAssertEqual(interval.schedule.next(after: at("2026-10-10 12:00"), clock: clock), at("2026-10-10 18:00"))
    }

    func testANextRunInThePast() {
        let job = jobs(Self.file)[0]
        let now = at("2026-10-13 12:00")
        XCTAssertEqual(job.schedule.next(after: now, clock: clock), at("2026-10-14 06:00"), "The expression says, 09:00 in Istanbul")
        let interval = jobs(Self.file)[1]
        XCTAssertNil(interval.schedule.next(after: now, clock: clock), "An interval counts from the last run, which only Hermes knows")
        XCTAssertNil(jobs(Self.file)[2].schedule.next(after: now, clock: clock), "A one time job that is over")
    }

    func testAnIntervalThatIsTooShortIsKnown() {
        let jobs = jobs(#"{"jobs":[{"id":"a","schedule":{"kind":"interval","minutes":10}},{"id":"b","schedule_display":"every 6h"},{"id":"c","schedule":{"display":"every 20m"}}]}"#)
        XCTAssertEqual(jobs.map { reported($0).everyMinutes }, [10, 360, 20])
        let now = at("2026-10-10 12:00")
        XCTAssertEqual(jobs.map { $0.schedule.runsMoreOften(than: 1800, now: now, clock: clock) }, [true, false, true])
    }

    func testTimes() {
        func date(_ value: Any?) -> Date? { HermesJobReader.date(value, timeZone: zone) }
        let want = at("2026-10-10 09:00")
        XCTAssertEqual(date("2026-10-10T09:00:00Z"), want)
        XCTAssertEqual(date("2026-10-10T12:00:00+03:00"), want)
        XCTAssertEqual(date("2026-10-10T12:00:00.5+03:00"), want)
        XCTAssertEqual(date("2026-10-10T12:00:00"), want)
        XCTAssertEqual(date("2026-10-10 12:00:00.123456"), want)
        XCTAssertEqual(date(want.timeIntervalSince1970), want)
        XCTAssertEqual(date(Int(want.timeIntervalSince1970) * 1000), want)
        for value in [nil, NSNull(), "", "soon", "2026-10-10", true, ["a"], 0, -5, 1e18, "1066-10-14T09:00:00Z"] as [Any?] {
            XCTAssertNil(date(value), String(describing: value))
        }
    }

    func testAFileThatIsNotUnderstoodGivesNoJobAndAReason() {
        func reason(_ text: String) -> String? {
            let result = HermesJobReader.jobs(Data(text.utf8), timeZone: zone)
            XCTAssertEqual(result.jobs, [], text)
            return result.reason
        }
        XCTAssertEqual(reason(""), "jobs.json is no JSON")
        XCTAssertEqual(reason("{\"jobs\": [{\"id\": "), "jobs.json is no JSON")
        XCTAssertEqual(reason("\u{0}\u{1}binary"), "jobs.json is no JSON")
        XCTAssertEqual(reason("{}"), "jobs.json has no list of jobs")
        XCTAssertEqual(reason(#"{"jobs": {"a": 1}}"#), "jobs.json has no list of jobs")
        XCTAssertEqual(reason(#"{"jobs": "none"}"#), "jobs.json has no list of jobs")
        XCTAssertNil(reason(#"{"jobs": []}"#), "An empty list is understood")
        XCTAssertNil(reason(#"{"jobs": [1, "a", {}, {"id": {"deep": true}, "schedule": 5, "next_run_at": []}]}"#))
        XCTAssertEqual(jobs(#"[{"id": "top", "schedule": "0 9 * * *"}]"#).map(\.id), ["hermes:top"], "A list with no key around it")
    }

    func testTheStatusOfTheSource() {
        let access = FixtureJobAccess()
        XCTAssertEqual(reader.read(access, timeZone: zone).status, JobSourceStatus.none, "No file is no failure")
        XCTAssertEqual(access.asked, ["/Users/fixture/.hermes/cron/jobs.json"])

        access.add(HermesJobReader.file, Data(Self.file.utf8))
        let reading = reader.read(access, timeZone: zone)
        XCTAssertEqual(reading.status, .ok)
        XCTAssertEqual(reading.jobs.count, 3)

        access.add(HermesJobReader.file, Data(#"{"jobs": []}"#.utf8))
        XCTAssertEqual(reader.read(access, timeZone: zone).status, JobSourceStatus.none)

        access.add(HermesJobReader.file, Data("not json".utf8))
        XCTAssertEqual(reader.read(access, timeZone: zone), JobSourceReading(source: .hermes, unreadable: "jobs.json is no JSON"))

        access.fail(HermesJobReader.file, "Permission denied")
        XCTAssertEqual(reader.read(access, timeZone: zone).status, .unreadable("Permission denied"))
    }
}
