import Foundation

/// A key runs every build released within a year of its purchase, for
/// ever. A build released later needs a new key, and Sparkle does not
/// offer it. Pure: the dates come from Polar and from the build.
enum UpdateWindow {
    static let length: TimeInterval = 365 * LicenseRules.day
    /// The key in Info.plist that `scripts/release.sh` fills with the time
    /// of the release, in UTC as `2026-10-23T09:30:00Z`.
    static let releaseDateKey = "ACReleaseDate"

    /// The last moment of a release that the key covers.
    static func end(purchased: Date) -> Date {
        purchased.addingTimeInterval(length)
    }

    /// Whether a key bought then runs a build released then. Without a
    /// purchase date (a key that Polar has not been asked about since the
    /// update) or without a release date (a build made without the release
    /// script) nothing is known, and the key runs.
    static func covers(release: Date?, purchased: Date?) -> Bool {
        guard let release, let purchased else { return true }
        return release <= end(purchased: purchased)
    }

    /// Whether Sparkle may offer an update with this date. Nil for the end
    /// while no key counts, as in the trial: every update is offered.
    static func offers(updateDated date: Date?, windowEnd: Date?) -> Bool {
        guard let windowEnd, let date else { return true }
        return date <= windowEnd
    }

    /// The end of the year of updates of the key that is activated here.
    /// Nil without an activation or before Polar said when it was bought.
    static func end(of record: LicenseRecord) -> Date? {
        guard record.activationID != nil, let purchased = record.purchased else { return nil }
        return end(purchased: purchased)
    }

    /// The key that is activated here does not run a build released then.
    static func keyTooOld(_ record: LicenseRecord, release: Date?) -> Bool {
        guard record.activationID != nil else { return false }
        return !covers(release: release, purchased: record.purchased)
    }

    /// The end Sparkle filters by: the year of updates of the key that is
    /// activated here, also while a check is late or the trial runs. Nil,
    /// so every update is offered, without an activation, and with a key
    /// that does not cover this build: a new key decides.
    static func sparkleWindowEnd(record: LicenseRecord, release: Date?) -> Date? {
        guard !keyTooOld(record, release: release) else { return nil }
        return end(of: record)
    }

    /// The release date of a build from its Info.plist value. Nil when it
    /// is missing, empty or not a date.
    static func releaseDate(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    /// A date as Polar writes it, with or without fractions of a second
    /// (`2026-10-23T09:30:00.123456Z`, `2026-10-23T09:30:00+00:00`).
    static func polarDate(_ text: String) -> Date? {
        let plain = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: plain)
    }
}
