import Foundation

/// How long the user pauses Agent Caffeine for.
enum PauseChoice: Equatable, CaseIterable {
    case thirtyMinutes
    case oneHour
    case untilTomorrow
}

/// A pause: Agent Caffeine acts as if it were off until a time of day,
/// then starts again by itself. Pure: the caller passes the time.
///
/// The end is a date on the wall clock, as in "paused until 15:30". So the
/// time the Mac sleeps counts as pause time: a Mac that slept past the end
/// wakes with the pause over. The other choice, a pause that only counts
/// the time awake, would end at a time nobody was told.
struct Pause: Equatable {
    /// The hour of "tomorrow", in local time.
    static let morningHour = 6
    /// A morning that is closer than this is today's, not tomorrow's: at
    /// 03:00 a pause until 06:00 would be three hours long.
    static let shortestNight: TimeInterval = 4 * 3600
    /// What "until tomorrow" is then.
    static let nightLength: TimeInterval = 8 * 3600
    /// No choice gives a longer pause: the next 06:00 is at most a day away,
    /// and an hour more when the clocks go back that night. An end that is
    /// further away means the clock was set back, and the pause is over.
    static let longest: TimeInterval = 25 * 3600

    /// Nil when not paused.
    private(set) var until: Date?

    init() {}

    /// From the date that was saved. A pause that ended while the app did
    /// not run is over.
    init(stored: Date?, now: Date) {
        until = stored
        settle(now: now)
    }

    static func deadline(for choice: PauseChoice, now: Date, calendar: Calendar) -> Date {
        switch choice {
        case .thirtyMinutes: return now.addingTimeInterval(30 * 60)
        case .oneHour: return now.addingTimeInterval(3600)
        case .untilTomorrow:
            let morning = calendar.nextDate(
                after: now, matching: DateComponents(hour: morningHour, minute: 0, second: 0), matchingPolicy: .nextTime
            )
            guard let morning, morning.timeIntervalSince(now) >= shortestNight else { return now.addingTimeInterval(nightLength) }
            return morning
        }
    }

    func isPaused(now: Date) -> Bool {
        guard let until else { return false }
        return now < until && until.timeIntervalSince(now) <= Self.longest
    }

    mutating func start(_ choice: PauseChoice, now: Date, calendar: Calendar) {
        until = Self.deadline(for: choice, now: now, calendar: calendar)
    }

    mutating func resume() {
        until = nil
    }

    /// Ends a pause whose time has come. Called at the end, after the Mac
    /// wakes, and after the clock was set.
    mutating func settle(now: Date) {
        if !isPaused(now: now) { until = nil }
    }
}

/// The switch and the pause together. `enabled` stays what the user set:
/// a pause never changes it.
struct PauseSwitch: Equatable {
    var enabled: Bool
    var pause: Pause

    /// The switch itself. Off ends a pause, and so does on: whoever
    /// switches Agent Caffeine on wants it on now.
    mutating func set(enabled: Bool) {
        self.enabled = enabled
        pause.resume()
    }

    /// The keyboard shortcut: a pause ends, else the switch turns over.
    mutating func toggle(now: Date) {
        if pause.isPaused(now: now) {
            pause.resume()
        } else {
            set(enabled: !enabled)
        }
    }
}
