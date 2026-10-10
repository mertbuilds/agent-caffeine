import XCTest

/// Times and clocks for the tests of scheduled jobs.
enum JobTime {
    static let losAngeles = "America/Los_Angeles"
    static let istanbul = "Europe/Istanbul"
    static let utc = "UTC"

    static func clock(_ zone: String = utc) -> JobClock {
        JobClock(timeZone: TimeZone(identifier: zone)!)
    }

    /// "2026-03-08 02:30" on the wall clock of the zone.
    static func date(_ text: String, _ zone: String = utc) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: zone)!
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    static func cron(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> CronExpression {
        guard let expression = CronExpression.parse(text) else {
            XCTFail("\(text) is no cron expression", file: file, line: line)
            return CronExpression(minutes: [], hours: [], days: [], months: [], weekdays: [], anyDay: true, anyWeekday: true)
        }
        return expression
    }
}
