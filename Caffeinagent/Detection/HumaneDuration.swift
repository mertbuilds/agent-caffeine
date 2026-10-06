import Foundation

/// A length of time in words, always with "for" or "ago": "for 12 minutes",
/// "1 hour 22 minutes ago", "a moment ago". Whole units that have passed,
/// never rounded up, and never abbreviated.
enum HumaneDuration {
    /// Below this many hours the minutes are said too.
    static let hoursWithMinutes = 10

    /// "for 12 minutes". Nil under a minute: the caller says what a moment
    /// means for its line.
    static func lasting(seconds: TimeInterval) -> String? {
        units(seconds: seconds).map { "for \($0)" }
    }

    static func lasting(minutes: Int) -> String? {
        lasting(seconds: TimeInterval(minutes) * 60)
    }

    /// "12 minutes ago", and "a moment ago" under a minute.
    static func ago(seconds: TimeInterval) -> String {
        "\(units(seconds: seconds) ?? "a moment") ago"
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// Minutes under an hour. Then hours with minutes, and no minutes on
    /// the full hour. From 10 hours on hours only, and from 2 days on
    /// days. Nil under a minute.
    private static func units(seconds: TimeInterval) -> String? {
        let minutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        if minutes < 1 { return nil }
        if minutes < 60 { return counted(minutes, "minute") }
        let hours = minutes / 60
        if hours < hoursWithMinutes {
            let rest = minutes % 60
            return rest == 0 ? counted(hours, "hour") : "\(counted(hours, "hour")) \(counted(rest, "minute"))"
        }
        if hours < 48 { return counted(hours, "hour") }
        return counted(hours / 24, "day")
    }
}
