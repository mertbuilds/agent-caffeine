import XCTest

final class LicenseRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = LicenseRules.day

    func testTrialDaysLeftAtDayBoundaries() {
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start), 7)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + 1), 7)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + day - 1), 7)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + day), 6)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + 5 * day), 2)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + 6 * day), 1)
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start, now: start + 7 * day - 1), 1)
        XCTAssertNil(LicenseRules.trialDaysLeft(start: start, now: start + 7 * day))
        XCTAssertNil(LicenseRules.trialDaysLeft(start: start, now: start + 30 * day))
    }

    func testFirstLaunchHasSevenDays() {
        let entitlement = LicenseRules.entitlement(record: LicenseRecord(), activationKnown: false, now: start)
        XCTAssertEqual(entitlement, .trial(daysLeft: 7))
    }

    /// A record of the paid builds up to 1.0.3 keeps its key, and its
    /// trial does not count: the trial starts again.
    func testTheTrialOfTheOldPaidBuildsDoesNotCount() throws {
        let old = #"{"key":"AGENTCAF-1","activationID":"a","trialStart":0,"latestSeen":0}"#
        let record = try JSONDecoder().decode(LicenseRecord.self, from: Data(old.utf8))
        XCTAssertEqual(record.key, "AGENTCAF-1")
        XCTAssertEqual(record.activationID, "a")
        XCTAssertNil(record.trialStart)
        let saved = try JSONEncoder().encode(LicenseRecord(trialStart: start))
        XCTAssertEqual(try JSONDecoder().decode(LicenseRecord.self, from: saved).trialStart, start)
    }

    func testClockSetBackCountsNoTimeBackwards() {
        let seen = start + 8 * day
        XCTAssertEqual(LicenseRules.effectiveNow(start, latestSeen: seen), seen)
        XCTAssertEqual(LicenseRules.effectiveNow(seen + 1, latestSeen: seen), seen + 1)
        var record = LicenseRecord(trialStart: start, latestSeen: seen)
        // Setting the clock back to the first day does not bring the trial back.
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start + day), .expired(.trialOver))
        record.latestSeen = start + 3 * day
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start), .trial(daysLeft: 4))
    }

    func testTrialStartInTheFutureCountsAsZeroElapsed() {
        XCTAssertEqual(LicenseRules.trialDaysLeft(start: start + day, now: start), 7)
    }

    func testOfflineGrace() {
        var record = LicenseRecord(key: "k", activationID: "a", lastValidated: start, trialStart: start - 100 * day)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, now: start + 30 * day), .licensed)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, now: start + 30 * day + 1), .expired(.unverified))
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start), .expired(.activationRemoved))
        record.trialStart = start
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start), .trial(daysLeft: 7))
    }

    func testExpiredReasons() {
        // Never licensed.
        var record = LicenseRecord(trialStart: start)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start + 8 * day), .expired(.trialOver))
        // Licensed, but Polar not reached for longer than the grace.
        record = LicenseRecord(key: "k", activationID: "a", lastValidated: start, trialStart: start)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, now: start + 31 * day), .expired(.unverified))
        // Licensed, the Keychain unreadable: only the mirrored check is known.
        record = LicenseRecord(lastValidated: start, trialStart: start)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, now: start + 31 * day), .expired(.unverified))
        // The activation was removed; the key text stays.
        record = LicenseRecord(key: "k", trialStart: start)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: false, now: start + 8 * day), .expired(.activationRemoved))
        XCTAssertFalse(Entitlement.expired(.unverified).allowsHolding)
        XCTAssertFalse(Entitlement.expired(.activationRemoved).allowsHolding)
    }

    func testLatestSeenCountsMeasuredTime() {
        // A clock that runs forward is the latest time.
        XCTAssertEqual(LicenseRules.latestSeen(previous: start, now: start + 3600, elapsed: 3600), start + 3600)
        XCTAssertEqual(LicenseRules.latestSeen(previous: nil, now: start, elapsed: nil), start)
        // Set back a month, the measured hour still counts.
        XCTAssertEqual(LicenseRules.latestSeen(previous: start, now: start - 30 * day, elapsed: 3600), start + 3600)
        // At launch nothing was measured: no time counts, none goes backwards.
        XCTAssertEqual(LicenseRules.latestSeen(previous: start, now: start - 30 * day, elapsed: nil), start)
        XCTAssertEqual(LicenseRules.latestSeen(previous: start, now: start - day, elapsed: -5), start)
    }
}
