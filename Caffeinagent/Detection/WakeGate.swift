import Foundation

/// After macOS says the Mac goes to sleep, Agent Caffeine starts no hold
/// and takes no sleep flag until the Mac woke in full and a sample from
/// after that wake was taken. Pure: the caller passes the events and the
/// time, in seconds the Mac was awake (`SampleGap.awakeSeconds`).
///
/// A sleeping Mac wakes by itself many times, for a few seconds, with the
/// display off (a dark wake). The app runs in them. What it knew before
/// the sleep is old then: a pause that ended in the night, or a state file
/// that still says "working", would take the sleep flag in a bag. macOS
/// tells an app of a wake only when the Mac wakes in full, and that word
/// opens the gate.
///
/// A Mac can also wake with the display off and stay awake: someone
/// connects over SSH, starts an agent and leaves. No word of a wake comes
/// then. So the gate also opens when the Mac was awake for longer than
/// `steadyAwake` with no sleep in between. It assumes that a dark wake
/// for maintenance is shorter than that: the longest one seen is 45
/// seconds (docs/research/07-display-and-remote-wake.md). Assumed, not
/// measured.
///
/// A hold that runs is not broken by the word of sleep alone. With a
/// closed lid on wall power the word comes and the Mac stays awake under
/// the power assertion. Only a real sleep ends the hold: the caller reads
/// it from the clock that counts the sleep (`SampleGap.asleepSeconds`),
/// so a sampling that stalled or a clock that was set ends nothing.
struct WakeGate: Equatable {
    /// Awake for longer than this with no sleep is no dark wake.
    static let steadyAwake: TimeInterval = 120

    /// macOS said the Mac goes to sleep, and no full wake came since.
    private var announced = false
    /// The Mac slept after that word.
    private var slept = false
    /// The Mac woke in full at this time, and no sample was taken since.
    private var wokeAt: TimeInterval?
    /// The Mac is awake with no sleep since this time. Set while `announced`.
    private var steadySince: TimeInterval?

    mutating func willSleep(awake now: TimeInterval) {
        announced = true
        wokeAt = nil
        steadySince = now
    }

    /// The Mac woke in full: macOS said so, or the displays came on.
    mutating func didWake(awake now: TimeInterval) {
        guard announced else { return }
        announced = false
        slept = false
        steadySince = nil
        wokeAt = now
    }

    /// - Parameters:
    ///   - awake: when the sample was taken.
    ///   - slept: the Mac slept between this sample and the one before it.
    /// - Returns: true when this sample opens the gate: it is the first
    ///   one after a full wake, or the Mac was awake for `steadyAwake`.
    @discardableResult
    mutating func sampled(awake: TimeInterval, slept: Bool) -> Bool {
        if announced {
            if slept {
                self.slept = true
                steadySince = awake
            } else if let steadySince, awake - steadySince > Self.steadyAwake {
                self = WakeGate()
                return true
            }
        } else if let wokeAt, awake >= wokeAt {
            self.wokeAt = nil
            return true
        }
        return false
    }

    /// Whether the decision may keep the Mac awake.
    /// - Parameter holding: the decision before it does.
    func allowsHold(holding: Bool) -> Bool {
        if slept { return false }
        if announced || wokeAt != nil { return holding }
        return true
    }
}

/// The time around an alarm of "Wake for jobs" in which its job hold may
/// start while the gate is closed: from 30 seconds before the alarm to
/// the end of the hold, which is the start grace after the time of the
/// job while the job was not seen, and the cap while it runs.
///
/// The alarm wakes a Mac with a closed lid without a full wake, so no
/// word of a wake comes and the gate stays closed. The job hold is new
/// evidence all the same: it comes from the clock and the schedule. What
/// the app knew of the agents before the sleep stays behind the gate.
struct AlarmWindow: Equatable {
    static let lead: TimeInterval = 30

    var alarmAt: Date
    var end: Date

    init(alarmAt: Date, end: Date) {
        self.alarmAt = alarmAt
        self.end = end
    }

    init(_ hold: JobHold) {
        self.init(alarmAt: hold.startedAt, end: hold.endsAt)
    }

    func contains(_ now: Date) -> Bool {
        now >= alarmAt.addingTimeInterval(-Self.lead) && now < end
    }
}

extension WakeGate {
    /// Whether a job hold may keep the Mac awake: when the gate is open,
    /// and inside the window of an alarm also while it is closed. Outside
    /// of every window the gate decides alone.
    /// - Parameter holding: the decision before it does.
    func allowsJobHold(holding: Bool, windows: [AlarmWindow], now: Date) -> Bool {
        allowsHold(holding: holding) || windows.contains { $0.contains(now) }
    }
}
