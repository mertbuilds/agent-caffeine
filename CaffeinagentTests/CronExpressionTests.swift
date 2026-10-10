import XCTest

final class CronExpressionTests: XCTestCase {
    private func next(_ text: String, after: String, zone: String = JobTime.utc, file: StaticString = #filePath, line: UInt = #line) -> Date? {
        JobTime.cron(text, file: file, line: line).next(after: JobTime.date(after, zone), clock: JobTime.clock(zone))
    }

    private func at(_ text: String, _ zone: String = JobTime.utc) -> Date { JobTime.date(text, zone) }

    // MARK: Fields

    func testEveryFormOfAField() {
        XCTAssertEqual(JobTime.cron("* * * * *").minutes.count, 60)
        XCTAssertEqual(JobTime.cron("0,30 * * * *").minutes, [0, 30])
        XCTAssertEqual(JobTime.cron("0 9-12 * * *").hours, [9, 10, 11, 12])
        XCTAssertEqual(JobTime.cron("*/15 * * * *").minutes, [0, 15, 30, 45])
        XCTAssertEqual(JobTime.cron("0-30/10 * * * *").minutes, [0, 10, 20, 30])
        XCTAssertEqual(JobTime.cron("5/20 * * * *").minutes, [5, 25, 45], "From 5 to the end")
        XCTAssertEqual(JobTime.cron("1,10-12,*/20 * * * *").minutes, [0, 1, 10, 11, 12, 20, 40])
        XCTAssertEqual(JobTime.cron("0 0 1 JAN,jun *").months, [1, 6])
        XCTAssertEqual(JobTime.cron("0 0 * Mar-May *").months, [3, 4, 5])
        XCTAssertEqual(JobTime.cron("0 0 * * MON-FRI").weekdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(JobTime.cron("0\t0  *\t* sat").weekdays, [6], "Tabs and more than one space")
    }

    func testSundayIsZeroAndSeven() {
        XCTAssertEqual(JobTime.cron("0 0 * * 0"), JobTime.cron("0 0 * * 7"))
        XCTAssertEqual(JobTime.cron("0 0 * * SUN"), JobTime.cron("0 0 * * 7"))
        XCTAssertEqual(JobTime.cron("0 0 * * 5-7").weekdays, [5, 6, 0])
        // 10 October 2026 is a Saturday.
        XCTAssertEqual(next("0 0 * * 7", after: "2026-10-10 12:00"), at("2026-10-11 00:00"))
    }

    func testTheWordsForCommonTimes() {
        XCTAssertEqual(JobTime.cron("@hourly"), JobTime.cron("0 * * * *"))
        XCTAssertEqual(JobTime.cron("@daily"), JobTime.cron("0 0 * * *"))
        XCTAssertEqual(JobTime.cron("@midnight"), JobTime.cron("0 0 * * *"))
        XCTAssertEqual(JobTime.cron("@weekly"), JobTime.cron("0 0 * * 0"))
        XCTAssertEqual(JobTime.cron("@monthly"), JobTime.cron("0 0 1 * *"))
        XCTAssertEqual(JobTime.cron("@yearly"), JobTime.cron("0 0 1 1 *"))
        XCTAssertEqual(JobTime.cron("@Annually"), JobTime.cron("0 0 1 1 *"))
        XCTAssertNil(CronExpression.parse("@reboot"), "A start of the Mac is no time")
        XCTAssertNil(CronExpression.parse("@every 5m"))
    }

    func testWhatIsNoExpression() {
        let refused = [
            "", "* * * *", "0 0 * * * *", "*/5 0 0 * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * 32 * *", "* * * 13 *",
            "* * * 0 *", "* * * * 8", "5-1 * * * *", "*/0 * * * *", "1,,2 * * * *", ", * * * *", "1- * * * *", "-1 * * * *",
            "1/2/3 * * * *", "0 0 ? * *", "0 0 L * *", "0 0 15W * *", "0 0 * * 5#3", "0 0 * * FRIDAY", "0 0 * FOO *", "a b c d e",
            "0 0 * * 1.5", "007 * * * *",
        ]
        for text in refused {
            XCTAssertNil(CronExpression.parse(text), text)
        }
    }

    func testTheKeyIsTheSameForTwoWaysToWriteOneSchedule() {
        XCTAssertEqual(JobTime.cron("*/30 * * * *").key, "0,30 * * * *")
        XCTAssertEqual(JobTime.cron("0,30 0-23 * * *").key, "0,30 * * * *")
        XCTAssertEqual(JobTime.cron("15 9 1 JAN MON").key, "15 9 1 1 1")
        XCTAssertEqual(JobTime.cron("@daily").key, "0 0 * * *")
    }

    // MARK: The next run

    func testTheNextRunIsAfterNow() {
        XCTAssertEqual(next("15 9 * * *", after: "2026-10-10 09:14"), at("2026-10-10 09:15"))
        XCTAssertEqual(next("15 9 * * *", after: "2026-10-10 09:15"), at("2026-10-11 09:15"), "Not the minute that is now")
        XCTAssertEqual(next("*/15 * * * *", after: "2026-10-10 23:50"), at("2026-10-11 00:00"))
        XCTAssertEqual(next("0 0 1 * *", after: "2026-12-31 23:59"), at("2027-01-01 00:00"))
        XCTAssertEqual(next("0 12 31 * *", after: "2026-09-01 00:00"), at("2026-10-31 12:00"), "September has no 31st")
        let seconds = at("2026-10-10 09:14").addingTimeInterval(59.5)
        XCTAssertEqual(JobTime.cron("15 9 * * *").next(after: seconds, clock: JobTime.clock()), at("2026-10-10 09:15"))
    }

    func testTheDayOfTheMonthOrTheDayOfTheWeek() {
        // 5 October 2026 is a Monday, the 9th a Friday, the 13th a Tuesday.
        XCTAssertEqual(next("0 0 13 * 5", after: "2026-10-05 00:00"), at("2026-10-09 00:00"), "The Friday comes first")
        XCTAssertEqual(next("0 0 13 * 5", after: "2026-10-09 00:00"), at("2026-10-13 00:00"), "Then the 13th, a Tuesday")
        XCTAssertEqual(next("0 0 13 * *", after: "2026-10-05 00:00"), at("2026-10-13 00:00"))
        XCTAssertEqual(next("0 0 * * 5", after: "2026-10-05 00:00"), at("2026-10-09 00:00"))
        // A field that begins with a star does not limit: both have to fit.
        XCTAssertEqual(next("0 0 */2 * 1", after: "2026-10-05 00:00"), at("2026-10-19 00:00"), "The 12th is a Monday with an even number")
    }

    func testLeapDay() {
        XCTAssertEqual(next("0 0 29 2 *", after: "2026-10-10 00:00"), at("2028-02-29 00:00"))
        XCTAssertEqual(next("0 0 29 2 *", after: "2028-02-29 00:00"), at("2032-02-29 00:00"))
        XCTAssertEqual(next("30 6 28-31 2 *", after: "2027-02-27 12:00"), at("2027-02-28 06:30"))
        XCTAssertEqual(next("30 6 28-31 2 *", after: "2027-02-28 12:00"), at("2028-02-28 06:30"))
        XCTAssertNil(next("0 0 30 2 *", after: "2026-10-10 00:00"), "30 February never comes")
    }

    // MARK: Clock changes

    func testATimeTheClockJumpsOverRunsAtTheJump() {
        // 8 March 2026, Los Angeles: 02:00 becomes 03:00.
        let zone = JobTime.losAngeles
        let jump = at("2026-03-08 10:00")
        XCTAssertEqual(next("30 2 * * *", after: "2026-03-08 00:00", zone: zone), jump)
        XCTAssertEqual(jump, at("2026-03-08 03:00", zone))
        XCTAssertEqual(JobTime.cron("30 2 * * *").next(after: jump, clock: JobTime.clock(zone)), at("2026-03-09 02:30", zone), "Once on that day")
        XCTAssertEqual(next("30 2 * * *", after: "2026-03-07 03:00", zone: zone), jump, "From the day before")
        // An hourly job runs once at the jump, not for 02:00 and again for 03:00.
        let hourly = JobSchedule.cron(JobTime.cron("0 * * * *")).fireTimes(after: at("2026-03-08 01:00", zone), count: 2, clock: JobTime.clock(zone))
        XCTAssertEqual(hourly, [jump, at("2026-03-08 04:00", zone)])
    }

    func testATimeThatComesTwiceRunsOnce() {
        // 1 November 2026, Los Angeles: 02:00 becomes 01:00.
        let zone = JobTime.losAngeles
        let first = at("2026-11-01 08:30"), second = at("2026-11-01 09:30")
        XCTAssertEqual(next("30 1 * * *", after: "2026-11-01 00:00", zone: zone), first)
        let clock = JobTime.clock(zone)
        XCTAssertEqual(JobTime.cron("30 1 * * *").next(after: first, clock: clock), at("2026-11-02 01:30", zone), "Not the second 01:30")
        XCTAssertEqual(JobTime.cron("30 1 * * *").next(after: second.addingTimeInterval(-600), clock: clock), at("2026-11-02 01:30", zone))
        XCTAssertEqual(JobTime.cron("0 2 * * *").next(after: second, clock: clock), at("2026-11-01 10:00"), "02:00 comes once, after both")
    }

    func testTheTimeZoneChangesBetweenTwoCalls() {
        let job = JobTime.cron("0 9 * * *")
        let now = at("2026-10-10 05:00")
        XCTAssertEqual(job.next(after: now, clock: JobTime.clock(JobTime.istanbul)), at("2026-10-10 06:00"), "09:00 in Istanbul")
        XCTAssertEqual(job.next(after: now, clock: JobTime.clock(JobTime.losAngeles)), at("2026-10-10 16:00"), "09:00 in Los Angeles")
        XCTAssertEqual(job.next(after: now, clock: JobTime.clock()), at("2026-10-10 09:00"))
    }

    func testTheCalendarOfTheUserDoesNotChangeTheDays() {
        // cron counts in the Gregorian calendar. Only the time zone is taken.
        let clock = JobClock(timeZone: TimeZone(identifier: JobTime.istanbul)!)
        XCTAssertEqual(clock.wall(at("2026-10-10 21:30")).day, JobClock.Day(year: 2026, month: 10, day: 11))
        XCTAssertEqual(clock.wall(at("2026-10-10 21:30")).minuteOfDay, 30)
        XCTAssertEqual(clock.weekday(JobClock.Day(year: 2026, month: 10, day: 10)), 6)
        XCTAssertEqual(clock.daysInMonth(year: 2028, month: 2), 29)
        XCTAssertNil(clock.instant(JobClock.Day(year: 2026, month: 2, day: 30), hour: 0, minute: 0))
    }

    // MARK: Schedules

    func testTheNextRunsInOrder() {
        let schedule = JobSchedule.cron(JobTime.cron("0 9,21 * * *"))
        XCTAssertEqual(
            schedule.fireTimes(after: at("2026-10-10 10:00"), count: 3, clock: JobTime.clock()),
            [at("2026-10-10 21:00"), at("2026-10-11 09:00"), at("2026-10-11 21:00")]
        )
        XCTAssertEqual(JobSchedule.cron(JobTime.cron("0 0 30 2 *")).fireTimes(after: at("2026-10-10 10:00"), count: 3, clock: JobTime.clock()), [])
    }

    func testAJobThatRunsMoreOftenThanEveryHalfHour() {
        let now = at("2026-10-10 10:07"), clock = JobTime.clock(), gap: TimeInterval = 1800
        func often(_ text: String) -> Bool { JobSchedule.cron(JobTime.cron(text)).runsMoreOften(than: gap, now: now, clock: clock) }
        XCTAssertTrue(often("* * * * *"))
        XCTAssertTrue(often("*/20 * * * *"))
        XCTAssertFalse(often("*/30 * * * *"), "Every half hour is offered")
        XCTAssertFalse(often("0 * * * *"))
        XCTAssertFalse(often("0,10 3 * * *"), "Two runs close together once a day")
        XCTAssertFalse(often("0 0 30 2 *"))
    }

    /// The answer is a switch in Settings, and it must not flip with the
    /// time of day. "*/45" runs at minute 0 and 45: 15 and 45 minutes
    /// apart, 48 times a day.
    func testTooOftenIsTheSameAtEveryTimeOfDay() {
        let clock = JobTime.clock()
        let cases: [(String, Bool)] = [
            ("*/45 * * * *", false), ("*/30 * * * *", false), ("*/20 * * * *", true), ("0,10,20,30 * * * *", true),
            ("0,5,10 9-17 * * *", false), ("*/10 9-17 * * *", true), ("0 * * * *", false), ("*/5 3 * * *", false),
        ]
        for (text, expected) in cases {
            let schedule = JobSchedule.cron(JobTime.cron(text))
            for minute in stride(from: 0, to: 24 * 60, by: 5) {
                let now = at("2026-10-10 00:00").addingTimeInterval(TimeInterval(minute * 60 + 7))
                XCTAssertEqual(schedule.runsMoreOften(than: 1800, now: now, clock: clock), expected, "\(text) at minute \(minute)")
            }
        }
        let calendar = JobSchedule.calendar([JobTime.cron("0 * * * *"), JobTime.cron("20 * * * *"), JobTime.cron("40 * * * *")])
        XCTAssertTrue(calendar.runsMoreOften(than: 1800, now: at("2026-10-10 10:07"), clock: clock), "72 runs a day in all")
    }
}
