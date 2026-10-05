import Foundation

/// A length of time in words: "a moment", "12 minutes", "6 hours", "3 days".
/// Whole units that have passed, never rounded up, and never abbreviated.
enum HumaneDuration {
    /// Under a minute is a moment. Minutes up to 89, then hours up to 47,
    /// then days.
    static func text(seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        if minutes < 1 { return "a moment" }
        if minutes < 90 { return counted(minutes, "minute") }
        let hours = minutes / 60
        if hours < 48 { return counted(hours, "hour") }
        return counted(hours / 24, "day")
    }

    static func text(minutes: Int) -> String {
        text(seconds: TimeInterval(minutes) * 60)
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
