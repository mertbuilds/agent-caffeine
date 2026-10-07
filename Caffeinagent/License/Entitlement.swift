import Foundation

/// Whether agent caffeine may keep the Mac awake.
enum Entitlement: Equatable {
    case licensed
    case trial(daysLeft: Int)
    case expired(ExpiredReason)

    var allowsHolding: Bool {
        if case .expired = self { return false }
        return true
    }
}

/// Why agent caffeine may not keep the Mac awake, so a paying user is never
/// told to buy a key.
enum ExpiredReason: Equatable {
    /// No key was activated here, and the trial is over.
    case trialOver
    /// This Mac's activation is stored, but Polar has not confirmed it for
    /// longer than the offline grace.
    case unverified
    /// A key is stored, but this Mac no longer holds an activation of it.
    case activationRemoved

    var text: String {
        switch self {
        case .trialOver: return "Your trial has ended. agent caffeine is not keeping your Mac awake."
        case .unverified: return "Your license was not checked for 30 days. Connect to the internet to keep your Mac awake."
        case .activationRemoved: return "This Mac is no longer activated for this key."
        }
    }
}

/// Everything the license state remembers between launches.
struct LicenseRecord: Codable, Equatable {
    /// The key as last entered. Kept after the activation is lost, so the user
    /// can activate again in one click.
    var key: String?
    /// This Mac's activation of `key`. Nil while the key is not activated here.
    var activationID: String?
    /// When Polar last said the activation is good.
    var lastValidated: Date?
    /// The first launch of a build with licensing.
    var trialStart: Date?
    /// The latest time the app has seen, so a clock set back counts no time
    /// backwards, and time the app measured itself still counts forward.
    var latestSeen: Date?
    /// On how many Macs the key runs, from Polar's answer to the
    /// activation. Nil when it did not say, and for a key that was
    /// activated by an older build.
    var macLimit: Int?
}

enum LicenseRules {
    static let day: TimeInterval = 86_400
    static let trialLength: TimeInterval = 7 * day
    /// How long a licensed Mac stays licensed without reaching Polar.
    static let offlineGrace: TimeInterval = 30 * day

    /// The clock as the license sees it: never earlier than a time it has
    /// already seen.
    static func effectiveNow(_ now: Date, latestSeen: Date?) -> Date {
        guard let latestSeen else { return now }
        return max(now, latestSeen)
    }

    /// The latest time seen after a refresh: the clock, or the previous latest
    /// time plus the time the process measured since the last refresh,
    /// whichever is later. A clock set back then neither stops the trial nor
    /// the offline grace while the app runs.
    /// - Parameter elapsed: seconds on a clock that counts during sleep and
    ///   ignores the wall clock. Nil at launch: time while the app was not
    ///   running cannot be measured, and is not counted.
    static func latestSeen(previous: Date?, now: Date, elapsed: TimeInterval?) -> Date {
        guard let previous else { return now }
        return max(now, previous + max(0, elapsed ?? 0))
    }

    /// Whole days left, counted in 24 hour periods from the start: 7 at first
    /// launch, 1 during the last 24 hours, nil once 7 days have passed.
    static func trialDaysLeft(start: Date, now: Date) -> Int? {
        let left = trialLength - max(0, now.timeIntervalSince(start))
        guard left > 0 else { return nil }
        return Int((left / day).rounded(.up))
    }

    /// - Parameter activationKnown: whether there is an activation to count
    ///   on. True without an activation id only while the stored activation
    ///   cannot be read, so the mirrored validation date still counts.
    static func entitlement(record: LicenseRecord, activationKnown: Bool, now: Date) -> Entitlement {
        let now = effectiveNow(now, latestSeen: record.latestSeen)
        if activationKnown, let lastValidated = record.lastValidated,
           now.timeIntervalSince(lastValidated) <= offlineGrace {
            return .licensed
        }
        guard let days = trialDaysLeft(start: record.trialStart ?? now, now: now) else {
            if activationKnown, record.lastValidated != nil { return .expired(.unverified) }
            return .expired(record.key == nil ? .trialOver : .activationRemoved)
        }
        return .trial(daysLeft: days)
    }
}
