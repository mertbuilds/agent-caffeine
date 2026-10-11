import Foundation

/// What Agent Caffeine knew at the moment macOS said the Mac goes to sleep.
struct SleepSnapshot: Equatable {
    var at: Date
    var headline: HoldHeadline
    /// An agent worked or waited for the user, and no rule ignores it.
    var agentActive: Bool
    /// Read at that moment, not from the last sample: a lid that closes
    /// puts the Mac to sleep before the next sample.
    var lidClosed = false
    var onBattery = false
    /// The helper for a closed lid on battery is allowed.
    var helperSetUp = false
    /// The setting "Stay awake with the lid closed on battery".
    var lidClosedWanted = true
    var waitingHold: TimeInterval = 300
    /// The agents that worked, by their display names, and no rule
    /// ignores them. Nil for none.
    var working: HoldSubject?
}

/// Why the Mac slept while an agent worked or waited.
enum SleepReason: Equatable {
    case lidClosedNoHelper
    case lidClosedSettingOff
    case battery(percent: Int)
    case tooHot
    case paused
    case notEntitled(ExpiredReason)
    case waitedTooLong(HoldSubject, hold: TimeInterval)
    /// The closed lid limit ended a hold, with the agents that still
    /// worked then.
    case closedLidLimit(ClosedLidStop, working: HoldSubject?)

    /// Nil when no agent worked or waited, when the user turned agent
    /// caffeine off, and when the reason is not known: with a hold and an
    /// open lid, or on power, the user put the Mac to sleep by hand.
    /// The closed lid limit is told with no agent too: it ends every kind
    /// of hold.
    static func reason(_ snapshot: SleepSnapshot) -> SleepReason? {
        if case .safetyStop(.closedLid(let stop)) = snapshot.headline { return .closedLidLimit(stop, working: snapshot.working) }
        guard snapshot.agentActive else { return nil }
        switch snapshot.headline {
        case .safetyStop(.batteryLow(let percent)), .safetyStop(.weakCharger(let percent)): return .battery(percent: percent)
        case .safetyStop(.tooHot): return .tooHot
        case .safetyStop(.closedLid(let stop)): return .closedLidLimit(stop, working: snapshot.working)
        case .paused: return .paused
        case .notEntitled(let reason): return .notEntitled(reason)
        case .waitingReleased(let subject): return .waitedTooLong(subject, hold: snapshot.waitingHold)
        case .switchedOff, .idle, .noAgents: return nil
        case .working, .waitingHeld, .finishedRecently, .open, .alwaysOn, .remoteAccess, .reachable, .manualHold, .scheduledJob:
            guard snapshot.lidClosed, snapshot.onBattery else { return nil }
            if !snapshot.helperSetUp { return .lidClosedNoHelper }
            return snapshot.lidClosedWanted ? nil : .lidClosedSettingOff
        }
    }
}

/// One line for the menu after the Mac woke. It stays until the user
/// dismisses it or the Mac sleeps again.
struct SleepNote: Equatable {
    var at: Date
    var reason: SleepReason

    init?(_ snapshot: SleepSnapshot) {
        guard let reason = SleepReason.reason(snapshot) else { return nil }
        at = snapshot.at
        self.reason = reason
    }

    init(at: Date, reason: SleepReason) {
        self.at = at
        self.reason = reason
    }
}
