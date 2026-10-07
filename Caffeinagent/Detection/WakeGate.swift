import Foundation

/// After macOS says the Mac goes to sleep, agent caffeine starts no hold
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
/// A hold that runs is not broken by the word of sleep alone. With a
/// closed lid on wall power the word comes and the Mac stays awake under
/// the power assertion. Only a hole between two samples shows that the
/// Mac did sleep, and then the hold ends.
struct WakeGate: Equatable {
    /// macOS said the Mac goes to sleep, and no full wake came since.
    private var announced = false
    /// A hole between two samples after that word: the Mac did sleep.
    private var slept = false
    /// The Mac woke in full at this time, and no sample was taken since.
    private var wokeAt: TimeInterval?

    mutating func willSleep() {
        announced = true
        wokeAt = nil
    }

    /// The Mac woke in full: macOS said so, or the displays came on.
    mutating func didWake(awake now: TimeInterval) {
        guard announced else { return }
        announced = false
        slept = false
        wokeAt = now
    }

    /// - Parameters:
    ///   - awake: when the sample was taken. Nil counts as now.
    ///   - gap: there is a hole between this sample and the one before it.
    /// - Returns: true when this is the first sample after a full wake.
    @discardableResult
    mutating func sampled(awake: TimeInterval?, gap: Bool) -> Bool {
        if announced {
            if gap { slept = true }
        } else if let wokeAt, awake.map({ $0 >= wokeAt }) ?? true {
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
