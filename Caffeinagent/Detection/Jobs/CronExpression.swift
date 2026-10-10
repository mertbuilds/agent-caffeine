import Foundation

/// The five time fields of a crontab line: minute, hour, day of the
/// month, month and day of the week. Only the times are kept, never the
/// command.
///
/// The rules are those of the cron of macOS (vixie cron):
///
/// - Lists (`1,15`), ranges (`1-5`), steps (`*/10`, `0-30/5`, `5/15` from
///   5 to the end) and the names `JAN` to `DEC` and `SUN` to `SAT`.
/// - Sunday is 0 and 7.
/// - When both the day of the month and the day of the week are limited,
///   the job runs on a day that fits either one. A field that begins with
///   `*` does not limit.
///
/// Any other dialect is refused, because the same text can mean another
/// day there: `?`, `L`, `W`, `#` and lines with a field for seconds.
struct CronExpression: Equatable {
    var minutes: Set<Int>
    var hours: Set<Int>
    var days: Set<Int>
    var months: Set<Int>
    /// 0 is Sunday.
    var weekdays: Set<Int>
    /// The day of the month does not limit the days.
    var anyDay: Bool
    /// The day of the week does not limit the days.
    var anyWeekday: Bool

    static let fieldCount = 5
    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let weekdayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    /// `@reboot` is none of these: it has no time.
    private static let descriptors = [
        "@hourly": "0 * * * *", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@weekly": "0 0 * * 0",
        "@monthly": "0 0 1 * *", "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *",
    ]

    /// The five fields of `@daily` and the like, nil for any other word.
    static func fields(ofDescriptor word: String) -> String? {
        descriptors[word.lowercased()]
    }

    /// Five fields with spaces or tabs between them, or one word such as
    /// `@daily`. Nil for anything else.
    static func parse(_ text: String) -> CronExpression? {
        var fields = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if fields.count == 1, let known = Self.fields(ofDescriptor: fields[0]) {
            fields = known.split(separator: " ").map(String.init)
        }
        guard fields.count == fieldCount,
              let minutes = values(fields[0], 0...59),
              let hours = values(fields[1], 0...23),
              let days = values(fields[2], 1...31),
              let months = values(fields[3], 1...12, names: monthNames, firstName: 1),
              let weekdays = values(fields[4], 0...7, names: weekdayNames, firstName: 0) else { return nil }
        return CronExpression(
            minutes: minutes, hours: hours, days: days, months: months, weekdays: Set(weekdays.map { $0 % 7 }),
            anyDay: fields[2].hasPrefix("*"), anyWeekday: fields[4].hasPrefix("*")
        )
    }

    /// The times as one text, the same for two ways to write one
    /// schedule. It is part of the id of a job.
    var key: String {
        func part(_ values: Set<Int>, _ count: Int, any: Bool = false) -> String {
            any || values.count == count ? "*" : values.sorted().map(String.init).joined(separator: ",")
        }
        return [part(minutes, 60), part(hours, 24), part(days, 31, any: anyDay), part(months, 12), part(weekdays, 7, any: anyWeekday)]
            .joined(separator: " ")
    }

    func runs(on day: JobClock.Day, weekday: Int) -> Bool {
        guard months.contains(day.month) else { return false }
        let dayFits = days.contains(day.day), weekdayFits = weekdays.contains(weekday)
        return anyDay || anyWeekday ? dayFits && weekdayFits : dayFits || weekdayFits
    }

    /// The first run after `now`. Nil for a schedule that never runs, as
    /// 30 February.
    func next(after now: Date, clock: JobClock) -> Date? {
        let start = clock.wall(now)
        let hours = self.hours.sorted(), minutes = self.minutes.sorted()
        var year = start.day.year, month = start.day.month, firstDay = start.day.day
        // 29 February on one day of the week can be 40 years away.
        for _ in 0..<(12 * 41) {
            if months.contains(month) {
                let last = clock.daysInMonth(year: year, month: month)
                for number in stride(from: firstDay, through: last, by: 1) {
                    let day = JobClock.Day(year: year, month: month, day: number)
                    guard runs(on: day, weekday: clock.weekday(day)) else { continue }
                    // No jump of a clock is longer than two hours, so an
                    // earlier time of today is over.
                    let earliest = day == start.day ? start.minuteOfDay - 120 : 0
                    for hour in hours {
                        for minute in minutes where hour * 60 + minute >= earliest {
                            if let date = clock.instant(day, hour: hour, minute: minute), date > now { return date }
                        }
                    }
                }
            }
            firstDay = 1
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
        return nil
    }

    // MARK: Fields

    private static func values(_ field: String, _ range: ClosedRange<Int>, names: [String] = [], firstName: Int = 0) -> Set<Int>? {
        var result: Set<Int> = []
        func number(_ text: Substring) -> Int? {
            if let index = names.firstIndex(of: text.lowercased()) { return index + firstName }
            guard !text.isEmpty, text.count <= 2, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text),
                  range.contains(value) else { return nil }
            return value
        }
        for part in field.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let base = pieces.first else { return nil }
            var step = 1
            if pieces.count == 2 {
                guard let value = number(pieces[1]), value > 0 else { return nil }
                step = value
            }
            let low: Int, high: Int
            if base == "*" {
                (low, high) = (range.lowerBound, range.upperBound)
            } else {
                let ends = base.split(separator: "-", omittingEmptySubsequences: false)
                guard ends.count <= 2, let first = number(ends[0]) else { return nil }
                if ends.count == 2 {
                    guard let second = number(ends[1]), first <= second else { return nil }
                    (low, high) = (first, second)
                } else {
                    (low, high) = (first, pieces.count == 2 ? range.upperBound : first)
                }
            }
            result.formUnion(stride(from: low, through: high, by: step))
        }
        return result.isEmpty ? nil : result
    }
}
