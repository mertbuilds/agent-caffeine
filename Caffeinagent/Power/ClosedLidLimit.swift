import Foundation

/// Why the closed lid limit ended a hold. Each case has the limit that
/// was reached, as it was set.
enum ClosedLidStop: Equatable {
    /// Agent Caffeine kept the Mac awake for this long with the lid closed
    /// on battery.
    case time(seconds: TimeInterval)
    /// The battery lost this many points with the lid closed.
    case drop(points: Int)
}

/// A last stop for a closed lid on battery. It asks no agent and no rule
/// of the detection: whatever keeps the Mac awake, a hold with the lid
/// closed on battery ends after a time, or after the battery lost a number
/// of points. So a job that hangs does not empty the battery in a bag.
///
/// One closed-lid period begins at the first sample that sees a hold with
/// the lid closed on battery. It ends when the lid opens or power comes,
/// and with nothing else: a hold that pauses and starts again while the
/// lid stays closed is the same period. The time is the total of the held
/// time in the period, and the drop is counted from the battery level at
/// its start.
///
/// The time is awake time (`SampleGap.interval`), so a sleep counts for
/// nothing, and a hole between two samples counts for nothing either.
///
/// A stop stays for the rest of the period. Opening the lid or connecting
/// power ends the period, and the next one starts fresh.
struct ClosedLidLimit: Equatable {
    static let defaultHours = 3
    static let hourChoices = [1, 2, 3, 6, 12]
    static let defaultDropPoints = 30
    static let dropChoices = [15, 30, 50]
    /// What a setting holds for "No limit".
    static let noLimit = 0
    /// A hidden default for the test runner: the time limit in seconds,
    /// in place of the hours of the settings. It is read at every sample,
    /// so `defaults write` from a Terminal sets it while the app runs.
    ///
    /// It counts only while the switch of the tests is on
    /// (`HoldStore.stateSwitchKey`), and it can only make the limit
    /// shorter: a value that is left over, or a large one, does not take
    /// the last stop away.
    static let testSecondsKey = "ClosedLidLimitSecondsForTests"

    /// The hidden default, 0 while the switch of the tests is off.
    static func testSeconds(in defaults: UserDefaults) -> TimeInterval {
        defaults.bool(forKey: HoldStore.stateSwitchKey) ? defaults.double(forKey: testSecondsKey) : 0
    }

    struct Period: Equatable {
        var since: Date
        /// Seconds Agent Caffeine kept the Mac awake in this period.
        var held: TimeInterval = 0
        /// Nil on a Mac that does not say its battery level.
        var percentAtStart: Int?
        var stop: ClosedLidStop?
    }

    /// Nil is no limit.
    var timeLimit: TimeInterval? = TimeInterval(defaultHours) * 3600
    /// In points of the battery level. Nil is no limit.
    var dropLimit: Int? = defaultDropPoints
    private(set) var period: Period?
    private var last: SampleTime?

    /// - Parameters:
    ///   - holding: Agent Caffeine kept the Mac awake up to this sample.
    ///   - afterGap: there is a hole between this sample and the one
    ///   before it (`SampleGap`).
    /// - Returns: the stop that is on, nil for none.
    mutating func update(_ context: FrameContext, holding: Bool, at time: SampleTime, afterGap: Bool = false) -> ClosedLidStop? {
        guard context.lidClosed, context.onBattery else {
            period = nil
            last = nil
            return nil
        }
        defer { last = time }
        guard var current = period else {
            if holding { period = Period(since: time.at, percentAtStart: context.batteryPercent) }
            return nil
        }
        if holding, !afterGap, let last { current.held += max(0, SampleGap.interval(from: last, to: time)) }
        // Only a hold is stopped. A period that holds nothing waits.
        if current.stop == nil, holding {
            if let timeLimit, current.held >= timeLimit {
                current.stop = .time(seconds: timeLimit)
            } else if let dropLimit, let start = current.percentAtStart, let percent = context.batteryPercent, start - percent >= dropLimit {
                current.stop = .drop(points: dropLimit)
            }
        }
        period = current
        return current.stop
    }
}

extension DetectionSettings {
    /// The limits of the settings. `testSeconds` is the hidden default
    /// (`ClosedLidLimit.testSeconds`). It counts when it is above zero,
    /// and never makes the time limit longer than the settings have it.
    func closedLidLimits(testSeconds: TimeInterval = 0) -> (time: TimeInterval?, drop: Int?) {
        let hours = closedLidLimitHours == ClosedLidLimit.noLimit ? nil : TimeInterval(closedLidLimitHours) * 3600
        return (
            testSeconds > 0 ? min(testSeconds, hours ?? testSeconds) : hours,
            closedLidLimitDrop == ClosedLidLimit.noLimit ? nil : closedLidLimitDrop
        )
    }
}
