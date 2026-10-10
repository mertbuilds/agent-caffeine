import Foundation

/// The wall clock of one time zone, for the fire times of scheduled jobs.
/// Pure: the time zone and the calendar are passed in, and the time is an
/// argument of every call.
///
/// cron and launchd count in the Gregorian calendar, so the calendar has
/// to be a Gregorian one. Only its rules for days and months are used:
/// the time zone of the calendar is not read.
struct JobClock {
    struct Day: Equatable {
        var year: Int
        var month: Int
        var day: Int
    }

    var timeZone: TimeZone
    /// The calendar in GMT, where no day has a jump.
    private var plain: Calendar

    init(timeZone: TimeZone, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.timeZone = timeZone
        plain = calendar
        plain.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    /// The day and the minute of the day that the clock on the wall shows.
    func wall(_ date: Date) -> (day: Day, minuteOfDay: Int) {
        let shifted = date.addingTimeInterval(TimeInterval(timeZone.secondsFromGMT(for: date)))
        let parts = plain.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
        return (Day(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// 0 is Sunday, as in cron.
    func weekday(_ day: Day) -> Int {
        guard let noon = plainDate(day, hour: 12, minute: 0) else { return 0 }
        return (plain.component(.weekday, from: noon) + 6) % 7
    }

    func daysInMonth(year: Int, month: Int) -> Int {
        guard let first = plainDate(Day(year: year, month: month, day: 1), hour: 0, minute: 0),
              let range = plain.range(of: .day, in: .month, for: first) else { return 28 }
        return range.count
    }

    /// When the clock on the wall shows this time on this day.
    ///
    /// - A time that does not exist, because the clock jumps over it, is
    ///   the moment of the jump: 02:30 on the day the clock goes from
    ///   02:00 to 03:00 is 03:00.
    /// - A time that exists twice, because the clock goes back, is the
    ///   first of the two, so a job runs once.
    func instant(_ day: Day, hour: Int, minute: Int) -> Date? {
        instants(day, hour: hour, minute: minute).first
    }

    /// The same, with both moments of a time that exists twice, the
    /// first one first. cron runs a job with `*` for the hour at both.
    func instants(_ day: Day, hour: Int, minute: Int) -> [Date] {
        guard let plainTime = plainDate(day, hour: hour, minute: minute) else { return [] }
        // The offsets on both sides of a jump that is near.
        let before = timeZone.secondsFromGMT(for: plainTime.addingTimeInterval(-86_400))
        let after = timeZone.secondsFromGMT(for: plainTime.addingTimeInterval(86_400))
        let candidates = [before, after].map { (offset: $0, date: plainTime.addingTimeInterval(TimeInterval(-$0))) }
        let real = Set(candidates.filter { timeZone.secondsFromGMT(for: $0.date) == $0.offset }.map(\.date)).sorted()
        if !real.isEmpty { return real }
        let dates = candidates.map(\.date)
        guard let low = dates.min(), let high = dates.max() else { return [] }
        return [jump(between: low, and: high)]
    }

    /// The first second with another offset than `low` has, up to `high`.
    private func jump(between low: Date, and high: Date) -> Date {
        let offset = timeZone.secondsFromGMT(for: low)
        guard timeZone.secondsFromGMT(for: high) != offset else { return high }
        var same = Int(low.timeIntervalSince1970.rounded(.down))
        var other = Int(high.timeIntervalSince1970.rounded(.up))
        while other - same > 1 {
            let middle = same + (other - same) / 2
            if timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(middle))) == offset {
                same = middle
            } else {
                other = middle
            }
        }
        return Date(timeIntervalSince1970: TimeInterval(other))
    }

    /// The time as if the wall clock were in GMT. Nil for a day that is
    /// not in the calendar, as 30 February.
    private func plainDate(_ day: Day, hour: Int, minute: Int) -> Date? {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = hour
        parts.minute = minute
        guard let date = plain.date(from: parts) else { return nil }
        let back = plain.dateComponents([.month, .day], from: date)
        return back.month == day.month && back.day == day.day ? date : nil
    }
}
