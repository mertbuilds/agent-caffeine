import Foundation

/// How long the user wants the Mac to stay reachable for.
enum ReachableChoice: Equatable, CaseIterable {
    case oneHour
    case twoHours
    case fourHours

    var length: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .twoHours: return 2 * 3600
        case .fourHours: return 4 * 3600
        }
    }
}

/// "Stay reachable": the Mac stays awake until a time of day, also when no
/// agent works, so a message from the phone reaches an agent in seconds.
/// The mirror of `Pause`, and pure like it: the caller passes the time.
///
/// The end is a date on the wall clock, as in "reachable until 18:30". A
/// Mac that slept past the end wakes with the time over.
struct Reachable: Equatable {
    /// What an awake, idle Mac with the lid closed uses, measured in
    /// `docs/research/07-display-and-remote-wake.md`: 0.7 to 1.0 percent
    /// of the battery per hour, against 0.3 to 0.4 asleep.
    static let batteryPercentPerHour = 1
    /// No choice lasts longer. An end that is further away means the clock
    /// was set back, and the time is over.
    static let longest: TimeInterval = 4 * 3600

    /// Nil when not on.
    private(set) var until: Date?

    init() {}

    /// From the date that was saved. A time that ended while the app did
    /// not run is over.
    init(stored: Date?, now: Date) {
        until = stored
        settle(now: now)
    }

    func isOn(now: Date) -> Bool {
        guard let until else { return false }
        return now < until && until.timeIntervalSince(now) <= Self.longest
    }

    mutating func start(_ choice: ReachableChoice, now: Date) {
        until = now.addingTimeInterval(choice.length)
    }

    mutating func stop() {
        until = nil
    }

    /// Ends a time that has come. Called at the end, after the Mac wakes,
    /// and after the clock was set.
    mutating func settle(now: Date) {
        if !isOn(now: now) { until = nil }
    }
}

/// The pause and "stay reachable" together. One is the opposite of the
/// other, so starting one ends the other.
struct TimedModes: Equatable {
    var pause = Pause()
    var reachable = Reachable()

    mutating func startPause(_ choice: PauseChoice, now: Date, calendar: Calendar) {
        reachable.stop()
        pause.start(choice, now: now, calendar: calendar)
    }

    mutating func startReachable(_ choice: ReachableChoice, now: Date) {
        pause.resume()
        reachable.start(choice, now: now)
    }

    /// The switch went off: nothing is left to pause or to keep awake.
    mutating func switchedOff() {
        pause.resume()
        reachable.stop()
    }

    /// A safety stop ends "stay reachable" for good: the Mac does not go
    /// back to it when the power returns or the Mac is cool.
    mutating func safetyStopped() {
        reachable.stop()
    }

    mutating func settle(now: Date) {
        pause.settle(now: now)
        reachable.settle(now: now)
    }
}
