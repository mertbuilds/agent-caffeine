import Foundation

/// Whether the helper does what it is asked, from how each try ended. Pure:
/// the caller passes the time, in seconds on a clock that only moves forward.
struct HelperHealth: Equatable {
    /// Trouble that lasts this long is told to the user. A helper that
    /// starts again answers well before that.
    static let patience: TimeInterval = 20
    /// This many tries in a row without an answer, and the helper is
    /// registered again.
    static let failuresBeforeRepair = 2

    private(set) var troubleSince: TimeInterval?
    private(set) var failures = 0
    /// The helper was registered again in this launch. Once is enough: a
    /// second time would not do what the first did not.
    private(set) var repairTried = false
    /// A repair ended and the helper still gives no answer. The user is
    /// told at once.
    private(set) var repairFailed = false

    /// The helper answered. A flag that is off while the app wants it on is
    /// trouble too. A flag that stays on is not: it is someone else's.
    mutating func answered(confirmed: Bool, wanted: Bool, now: TimeInterval) {
        failures = 0
        repairFailed = false
        if wanted && !confirmed {
            troubleSince = troubleSince ?? now
        } else {
            troubleSince = nil
        }
    }

    /// A try ended with an error or with no answer in time.
    mutating func failed(now: TimeInterval) {
        failures += 1
        troubleSince = troubleSince ?? now
    }

    /// The helper is not enabled, so nothing is asked of it.
    mutating func helperIsOff() {
        failures = 0
        repairFailed = false
        troubleSince = nil
    }

    func notResponding(now: TimeInterval) -> Bool {
        repairFailed || troubleSince.map { now - $0 >= Self.patience } ?? false
    }

    /// True when the helper is to be registered again now, once in a launch.
    /// - Parameter atOnce: do not wait for more failures.
    mutating func takeRepair(atOnce: Bool = false) -> Bool {
        guard !repairTried, atOnce || failures >= Self.failuresBeforeRepair else { return false }
        repairTried = true
        return true
    }

    mutating func repairDidFail() {
        repairTried = true
        repairFailed = true
    }

    /// The user asked for a repair.
    mutating func repairAsked() {
        repairTried = true
    }
}
