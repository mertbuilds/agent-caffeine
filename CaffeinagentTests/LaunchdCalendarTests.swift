import XCTest

final class LaunchdCalendarTests: XCTestCase {
    private let clock = JobTime.clock()

    private func at(_ text: String, _ zone: String = JobTime.utc) -> Date { JobTime.date(text, zone) }

    private func schedule(_ value: Any, file: StaticString = #filePath, line: UInt = #line) -> JobSchedule {
        guard let entries = LaunchdCalendar.entries(value) else {
            XCTFail("No calendar", file: file, line: line)
            return .calendar([])
        }
        return .calendar(entries)
    }

    func testADictionary() {
        let daily = schedule(["Hour": 9, "Minute": 15])
        XCTAssertEqual(daily.next(after: at("2026-10-10 09:14"), clock: clock), at("2026-10-10 09:15"))
        XCTAssertEqual(daily.next(after: at("2026-10-10 09:15"), clock: clock), at("2026-10-11 09:15"))
        XCTAssertEqual(LaunchdCalendar.entries(["Hour": 9, "Minute": 15]), [JobTime.cron("15 9 * * *")])
    }

    func testMissingKeysFitEveryValue() {
        XCTAssertEqual(LaunchdCalendar.entry(["Minute": 30]), JobTime.cron("30 * * * *"))
        XCTAssertEqual(LaunchdCalendar.entry(["Hour": 3]), JobTime.cron("* 3 * * *"), "Every minute of that hour")
        XCTAssertEqual(LaunchdCalendar.entry([:]), JobTime.cron("* * * * *"))
        XCTAssertEqual(LaunchdCalendar.entry(["Month": 2, "Day": 29, "Hour": 0, "Minute": 0]), JobTime.cron("0 0 29 2 *"))
        XCTAssertEqual(LaunchdCalendar.entry(["Minute": 0, "Hour": 0, "ProgramArguments": ["x"]]), JobTime.cron("0 0 * * *"), "Other keys are not read")
    }

    func testWeekdayZeroAndSevenAreSunday() {
        XCTAssertEqual(LaunchdCalendar.entry(["Weekday": 0, "Hour": 8, "Minute": 0]), LaunchdCalendar.entry(["Weekday": 7, "Hour": 8, "Minute": 0]))
        // 10 October 2026 is a Saturday.
        XCTAssertEqual(schedule(["Weekday": 7, "Hour": 8, "Minute": 0]).next(after: at("2026-10-10 12:00"), clock: clock), at("2026-10-11 08:00"))
    }

    func testTheDayOrTheWeekday() {
        // 9 October 2026 is a Friday, the 13th a Tuesday.
        let either = schedule(["Day": 13, "Weekday": 5, "Hour": 0, "Minute": 0])
        XCTAssertEqual(
            either.fireTimes(after: at("2026-10-05 00:00"), count: 2, clock: clock), [at("2026-10-09 00:00"), at("2026-10-13 00:00")]
        )
    }

    func testAnArrayThatDiffersInOneField() {
        let twice = schedule([["Hour": 9, "Minute": 0], ["Hour": 21, "Minute": 0]])
        XCTAssertEqual(
            twice.fireTimes(after: at("2026-10-10 10:00"), count: 3, clock: clock),
            [at("2026-10-10 21:00"), at("2026-10-11 09:00"), at("2026-10-11 21:00")]
        )
    }

    func testAnArrayThatDiffersInTwoFieldsKeepsEveryTime() {
        let value: [[String: Any]] = [["Hour": 9, "Minute": 15], ["Hour": 18, "Minute": 40], ["Weekday": 1, "Hour": 3, "Minute": 5]]
        XCTAssertEqual(LaunchdCalendar.entries(value)?.count, 3)
        // 12 October 2026 is a Monday.
        XCTAssertEqual(
            schedule(value).fireTimes(after: at("2026-10-11 10:00"), count: 4, clock: clock),
            [at("2026-10-11 18:40"), at("2026-10-12 03:05"), at("2026-10-12 09:15"), at("2026-10-12 18:40")]
        )
    }

    func testTheSameDictionaryTwiceIsOneEntry() {
        XCTAssertEqual(LaunchdCalendar.entries([["Hour": 9, "Minute": 0], ["Minute": 0, "Hour": 9]])?.count, 1)
    }

    func testWhatIsNoCalendar() {
        XCTAssertNil(LaunchdCalendar.entries(nil))
        XCTAssertNil(LaunchdCalendar.entries(3600))
        XCTAssertNil(LaunchdCalendar.entries("0 9 * * *"))
        XCTAssertNil(LaunchdCalendar.entries([[String: Any]]()))
        XCTAssertNil(LaunchdCalendar.entries([["Hour": 9], "x"] as [Any]))
        XCTAssertNil(LaunchdCalendar.entries(["Minute": 60]))
        XCTAssertNil(LaunchdCalendar.entries(["Hour": 24]))
        XCTAssertNil(LaunchdCalendar.entries(["Day": 0]))
        XCTAssertNil(LaunchdCalendar.entries(["Month": 13]))
        XCTAssertNil(LaunchdCalendar.entries(["Weekday": 8]))
        XCTAssertNil(LaunchdCalendar.entries(["Hour": "9"]))
        XCTAssertNil(LaunchdCalendar.entries(["Hour": 9.5]))
        XCTAssertNil(LaunchdCalendar.entries(["Hour": true]))
        XCTAssertNil(LaunchdCalendar.entries([["Hour": 9, "Minute": 0], ["Hour": 99]]), "One wrong entry, and the job is not offered")
    }

    func testTheClockChangesAsForCron() {
        let zone = JobTime.losAngeles, clock = JobTime.clock(zone)
        let spring = schedule(["Hour": 2, "Minute": 30])
        XCTAssertEqual(spring.next(after: at("2026-03-08 00:00", zone), clock: clock), at("2026-03-08 03:00", zone))
        let autumn = schedule(["Hour": 1, "Minute": 30])
        let first = at("2026-11-01 08:30")
        XCTAssertEqual(autumn.next(after: at("2026-11-01 00:00", zone), clock: clock), first)
        XCTAssertEqual(autumn.next(after: first, clock: clock), at("2026-11-02 01:30", zone))
    }
}
