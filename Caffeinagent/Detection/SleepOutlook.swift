import Foundation

/// What the Mac itself does about sleep. All of it is read with no
/// permission.
struct MacSleepState: Equatable {
    var lidClosed = false
    var onBattery = false
    /// The sleep flag of the helper is set: with the lid closed on battery
    /// the Mac is awake only for as long as Agent Caffeine holds.
    var flagInUse = false
    /// The system sleep timer of macOS for the power source in use, in
    /// minutes. 0 is never. Nil when it was not read.
    var sleepTimerMinutes: Int?
    /// Another app asks the Mac to stay awake.
    var otherAppHolds = false
}

/// What happens when the hold for the agents that wait ends. It speaks for
/// the whole Mac, so the menu and a notification say the same.
enum SleepOutlook: Equatable {
    /// What the Mac does once Agent Caffeine lets go with the lid open.
    /// Only what rules sleep out is known for sure, so no line says when
    /// the Mac sleeps from this.
    enum Afterwards: Equatable {
        case unknown
        /// The sleep timer of macOS starts to count.
        case sleepTimer(minutes: Int)
        /// The sleep timer of macOS is set to never.
        case neverSleeps
        case otherAppHolds
    }

    /// Something else keeps the Mac awake, or nothing does. Nothing is
    /// said about sleep.
    case silent
    /// The lid is closed on battery and only the sleep flag keeps the Mac
    /// awake, so it sleeps when Agent Caffeine lets go.
    case sleeps(after: TimeInterval)
    /// Agent Caffeine lets go then. What the Mac does next is its own.
    case letsGo(after: TimeInterval, then: Afterwards)

    init(_ decision: HoldDecision, mac: MacSleepState, now: Date) {
        guard decision.hold, let left = decision.waitingEnds?.timeIntervalSince(now), left > 0 else {
            self = .silent
            return
        }
        // macOS sleeps a Mac with the lid closed on battery whatever
        // another app asks for, so nothing takes this one back.
        if mac.lidClosed, mac.onBattery, mac.flagInUse, decision.lidClosedFlag {
            self = .sleeps(after: left)
            return
        }
        self = .letsGo(after: left, then: Self.afterwards(mac))
    }

    private static func afterwards(_ mac: MacSleepState) -> Afterwards {
        if mac.otherAppHolds { return .otherAppHolds }
        guard let minutes = mac.sleepTimerMinutes else { return .unknown }
        return minutes == 0 ? .neverSleeps : .sleepTimer(minutes: minutes)
    }

    /// For the log: times only.
    var logLine: String {
        switch self {
        case .silent: return "sleep outlook: nothing said"
        case .sleeps(let after): return "sleep outlook: the Mac sleeps in \(Int(after.rounded())) s"
        case .letsGo(let after, let then):
            let next: String
            switch then {
            case .unknown: next = "the sleep timer of macOS is not known"
            case .sleepTimer(let minutes): next = "the sleep timer of macOS is \(minutes) min"
            case .neverSleeps: next = "macOS never sleeps on this power source"
            case .otherAppHolds: next = "another app keeps the Mac awake"
            }
            return "sleep outlook: Agent Caffeine lets go in \(Int(after.rounded())) s, \(next)"
        }
    }
}
