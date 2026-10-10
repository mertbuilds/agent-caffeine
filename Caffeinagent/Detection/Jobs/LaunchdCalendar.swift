import Foundation

/// `StartCalendarInterval` of a launchd plist as times
/// (`launchd.plist(5)`): a dictionary, or an array of dictionaries, with
/// the keys `Minute`, `Hour`, `Day`, `Weekday` and `Month`.
///
/// - A key that is missing fits every value, so an empty dictionary runs
///   every minute.
/// - `Weekday` 0 and 7 are Sunday.
/// - With both `Day` and `Weekday` the job runs on a day that fits either
///   one, as in cron.
/// - Each dictionary of an array is a schedule of its own, and the job
///   runs when any of them does. All of them are kept.
///
/// The clock changes are handled as for cron, see `JobClock.instant`.
enum LaunchdCalendar {
    static let key = "StartCalendarInterval"

    /// One entry per dictionary. Nil for a value that is no calendar, and
    /// for one with a number out of range: a schedule that is partly
    /// wrong is not offered.
    static func entries(_ value: Any?) -> [CronExpression]? {
        let dictionaries: [[String: Any]]
        if let one = value as? [String: Any] {
            dictionaries = [one]
        } else if let many = value as? [[String: Any]], !many.isEmpty {
            dictionaries = many
        } else {
            return nil
        }
        var entries: [CronExpression] = []
        for dictionary in dictionaries {
            guard let entry = entry(dictionary) else { return nil }
            if !entries.contains(entry) { entries.append(entry) }
        }
        return entries
    }

    static func entry(_ dictionary: [String: Any]) -> CronExpression? {
        guard let minute = number(dictionary["Minute"], 0...59),
              let hour = number(dictionary["Hour"], 0...23),
              let day = number(dictionary["Day"], 1...31),
              let weekday = number(dictionary["Weekday"], 0...7),
              let month = number(dictionary["Month"], 1...12) else { return nil }
        return CronExpression(
            minutes: minute.map { [$0] } ?? Set(0...59),
            hours: hour.map { [$0] } ?? Set(0...23),
            days: day.map { [$0] } ?? Set(1...31),
            months: month.map { [$0] } ?? Set(1...12),
            weekdays: weekday.map { [$0 % 7] } ?? Set(0...6),
            anyDay: day == nil, anyWeekday: weekday == nil, anyHour: hour == nil
        )
    }

    /// `.some(nil)` for a key that is missing, nil for a value that is no
    /// whole number in the range.
    private static func number(_ value: Any?, _ range: ClosedRange<Int>) -> Int??  {
        guard let value else { return .some(nil) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue), range.contains(number.intValue) else { return nil }
        return number.intValue
    }
}
