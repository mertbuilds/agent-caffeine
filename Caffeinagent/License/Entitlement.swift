import Foundation

/// Whether Agent Caffeine may keep the Mac awake.
enum Entitlement: Equatable {
    case licensed
    case trial(daysLeft: Int)
    case expired(ExpiredReason)

    var allowsHolding: Bool {
        if case .expired = self { return false }
        return true
    }
}

/// Why Agent Caffeine may not keep the Mac awake, so a paying user is never
/// told to buy a key.
enum ExpiredReason: Equatable {
    /// No key was activated here, and the trial is over.
    case trialOver
    /// This Mac's activation is stored, but Polar has not confirmed it for
    /// longer than the offline grace.
    case unverified
    /// A key is stored, but this Mac no longer holds an activation of it.
    case activationRemoved
    /// The key is good, and this build was released after the year of
    /// updates of the key ended. Older builds keep running with it.
    case updatesEnded(coveredUntil: Date)

    var text: String {
        switch self {
        case .trialOver: return "Your trial has ended. Agent Caffeine is not keeping your Mac awake."
        case .unverified: return "Your license was not checked for 30 days. Connect to the internet to keep your Mac awake."
        case .activationRemoved: return "This Mac is no longer activated for this key."
        case .updatesEnded(let until): return LicenseRules.coveredUntil(until)
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
    /// The first launch of a paid build after the free 1.1 builds. Stored
    /// under a name of its own: the trial of the paid builds up to 1.0.3
    /// does not count, so whoever comes from them or from the free builds
    /// gets a full trial.
    var trialStart: Date?
    /// The latest time the app has seen, so a clock set back counts no time
    /// backwards, and time the app measured itself still counts forward.
    var latestSeen: Date?
    /// On how many Macs the key runs, from Polar's answer to the
    /// activation. Nil when it did not say, and for a key that was
    /// activated by an older build.
    var macLimit: Int?
    /// When the key was bought, from Polar's answers. It starts the year of
    /// updates (`UpdateWindow`). Nil until Polar was asked about the key.
    var purchased: Date?

    enum CodingKeys: String, CodingKey {
        case key
        case activationID
        case lastValidated
        case trialStart = "trialStart2"
        case latestSeen
        case macLimit
        case purchased
    }
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
    /// - Parameter release: when this build was released. A key whose year
    ///   of updates ended before it counts as no key, and the trial runs.
    static func entitlement(record: LicenseRecord, activationKnown: Bool, release: Date? = nil, now: Date) -> Entitlement {
        let now = effectiveNow(now, latestSeen: record.latestSeen)
        var windowEnded: Date?
        if activationKnown, let lastValidated = record.lastValidated,
           now.timeIntervalSince(lastValidated) <= offlineGrace {
            guard !UpdateWindow.covers(release: release, purchased: record.purchased),
                  let purchased = record.purchased else { return .licensed }
            windowEnded = UpdateWindow.end(purchased: purchased)
        }
        guard let days = trialDaysLeft(start: record.trialStart ?? now, now: now) else {
            if let windowEnded { return .expired(.updatesEnded(coveredUntil: windowEnded)) }
            if activationKnown, record.lastValidated != nil { return .expired(.unverified) }
            return .expired(record.key == nil ? .trialOver : .activationRemoved)
        }
        return .trial(daysLeft: days)
    }

    /// "Your key covers versions released until October 23, 2027."
    static func coveredUntil(_ end: Date) -> String {
        "Your key covers versions released until \(end.formatted(date: .long, time: .omitted))."
    }
}
