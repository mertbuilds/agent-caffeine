import XCTest

/// A key runs every build released within a year of its purchase, and
/// Sparkle offers no later one.
@MainActor
final class UpdateWindowTests: XCTestCase {
    private let day = LicenseRules.day
    private let bought = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { bought + 365 * day }

    // MARK: Date math

    func testTheWindowIsOneYearFromThePurchase() {
        XCTAssertEqual(UpdateWindow.end(purchased: bought), bought + 365 * day)
    }

    func testTheWindowCoversABuildReleasedInIt() {
        XCTAssertTrue(UpdateWindow.covers(release: bought - day, purchased: bought), "A build older than the key")
        XCTAssertTrue(UpdateWindow.covers(release: bought + 200 * day, purchased: bought))
        XCTAssertTrue(UpdateWindow.covers(release: end, purchased: bought), "The last moment counts")
    }

    func testTheWindowEndedBeforeALaterBuild() {
        XCTAssertFalse(UpdateWindow.covers(release: end + 1, purchased: bought))
        XCTAssertFalse(UpdateWindow.covers(release: bought + 400 * day, purchased: bought))
    }

    /// Nothing known locks nobody out.
    func testAMissingDateCoversTheBuild() {
        XCTAssertTrue(UpdateWindow.covers(release: bought + 900 * day, purchased: nil), "No purchase date yet")
        XCTAssertTrue(UpdateWindow.covers(release: nil, purchased: bought), "A build without a release date")
        XCTAssertTrue(UpdateWindow.covers(release: nil, purchased: nil))
    }

    // MARK: Dates of the build and of Polar

    func testTheReleaseDateOfTheBuild() {
        XCTAssertEqual(UpdateWindow.releaseDate("2026-10-23T09:30:00Z"), Date(timeIntervalSince1970: 1_792_747_800))
        XCTAssertNil(UpdateWindow.releaseDate(nil))
        XCTAssertNil(UpdateWindow.releaseDate(""), "A build made without the release script")
        XCTAssertNil(UpdateWindow.releaseDate("$(AC_RELEASE_DATE)"))
        XCTAssertNil(UpdateWindow.releaseDate(42))
    }

    func testPolarDatesWithAndWithoutFractions() {
        let date = Date(timeIntervalSince1970: 1_792_747_800)
        XCTAssertEqual(UpdateWindow.polarDate("2026-10-23T09:30:00Z"), date)
        XCTAssertEqual(UpdateWindow.polarDate("2026-10-23T09:30:00.123456Z"), date)
        XCTAssertEqual(UpdateWindow.polarDate("2026-10-23T09:30:00.5+00:00"), date)
        XCTAssertNil(UpdateWindow.polarDate("yesterday"))
    }

    // MARK: Entitlement

    private func record(purchased: Date?, trialStart: Date) -> LicenseRecord {
        var record = LicenseRecord(key: "k", activationID: "a", lastValidated: trialStart, trialStart: trialStart)
        record.purchased = purchased
        return record
    }

    func testAKeyRunsABuildOfItsYear() {
        let now = bought + 500 * day
        let record = record(purchased: bought, trialStart: now)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, release: bought + 300 * day, now: now), .licensed)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, release: nil, now: now), .licensed)
    }

    /// The key counts as none: the trial runs, then the app stops and
    /// names the end of the window.
    func testAKeyWhoseWindowEndedIsNoKeyForALaterBuild() {
        let release = end + day
        let start = bought + 500 * day
        let record = record(purchased: bought, trialStart: start)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, release: release, now: start), .trial(daysLeft: 7))
        var later = record
        later.lastValidated = start + 8 * day
        XCTAssertEqual(
            LicenseRules.entitlement(record: later, activationKnown: true, release: release, now: start + 8 * day),
            .expired(.updatesEnded(coveredUntil: end))
        )
    }

    func testAKeyWithoutAPurchaseDateRunsTheBuild() {
        let now = bought + 900 * day
        let record = record(purchased: nil, trialStart: now - 30 * day)
        XCTAssertEqual(LicenseRules.entitlement(record: record, activationKnown: true, release: now, now: now), .licensed)
    }

    func testTheTextsOfTheWindow() {
        let end = ISO8601DateFormatter().date(from: "2027-10-23T12:00:00Z")!
        XCTAssertTrue(LicenseRules.coveredUntil(end).hasPrefix("Your key covers versions released until "))
        XCTAssertTrue(PanelText.updates(until: end, now: end - day).hasPrefix("Updates until "))
        XCTAssertTrue(PanelText.updates(until: end, now: end + day).hasPrefix("Updates ended on "))
        XCTAssertEqual(
            MenuModel.state(PanelInput(
                decision: HoldDecision(hold: false, lidClosedFlag: false, headline: .notEntitled(.updatesEnded(coveredUntil: end)), perAgent: []),
                entitlement: .expired(.updatesEnded(coveredUntil: end)), hasLicenseKey: true
            ), now: end).attention?.actions,
            [.buy, .enterKey]
        )
    }

    // MARK: The manager

    private func manager(_ api: StubLicenseAPI, _ store: MemoryLicenseStore, release: Date?, now: Date) -> LicenseManager {
        LicenseManager(client: api, store: store, defaults: TestDefaults(), label: "Mac14,2", release: release, now: { now }, uptime: { 0 })
    }

    func testTheActivationAndEachCheckKeepThePurchaseDate() async {
        let api = StubLicenseAPI()
        let store = MemoryLicenseStore()
        let now = bought + 10 * day
        let manager = manager(api, store, release: bought + 5 * day, now: now)
        api.activation = .activated(id: "act-1", macs: 3, purchased: bought)
        await manager.activate(key: "AGENTCAF-1")
        XCTAssertEqual(store.record?.purchased, bought)
        XCTAssertEqual(manager.updatesEnd, end)
        XCTAssertFalse(manager.keyTooOldForThisBuild)
        XCTAssertEqual(manager.entitlement, .licensed)

        // An answer without the date keeps the one that is known.
        api.validation = .valid(purchased: nil)
        await manager.validate()
        XCTAssertEqual(store.record?.purchased, bought)
    }

    /// A key activated by a build before the window had no date: the
    /// first check fills it in.
    func testACheckFillsInTheDateOfAnOlderActivation() async {
        let api = StubLicenseAPI()
        let store = MemoryLicenseStore()
        let now = bought + 800 * day
        store.record = LicenseRecord(key: "AGENTCAF-1", activationID: "act-1", lastValidated: now, trialStart: now - 30 * day)
        let manager = manager(api, store, release: now - day, now: now)
        XCTAssertEqual(manager.entitlement, .licensed, "Nothing is known yet")
        api.validation = .valid(purchased: bought)
        await manager.validate()
        XCTAssertTrue(manager.keyTooOldForThisBuild)
        XCTAssertEqual(manager.entitlement, .expired(.updatesEnded(coveredUntil: end)))
    }

    // MARK: Sparkle

    func testSparkleOffersOnlyTheUpdatesOfTheWindow() {
        XCTAssertTrue(UpdateWindow.offers(updateDated: end - day, windowEnd: end))
        XCTAssertTrue(UpdateWindow.offers(updateDated: end, windowEnd: end))
        XCTAssertFalse(UpdateWindow.offers(updateDated: end + 1, windowEnd: end))
        XCTAssertTrue(UpdateWindow.offers(updateDated: nil, windowEnd: end), "An item without a date")
        XCTAssertTrue(UpdateWindow.offers(updateDated: end + 900 * day, windowEnd: nil), "No window: every update")
    }

    /// The window comes from the key, not from the entitlement of the
    /// moment: a late check or the trial does not open it.
    func testTheWindowForSparkleComesFromTheActivatedKey() {
        var record = LicenseRecord(key: "k", activationID: "a", lastValidated: bought)
        record.purchased = bought
        XCTAssertEqual(UpdateWindow.sparkleWindowEnd(record: record, release: bought + day), end)
        XCTAssertEqual(UpdateWindow.sparkleWindowEnd(record: record, release: nil), end)
        record.lastValidated = nil
        XCTAssertEqual(UpdateWindow.sparkleWindowEnd(record: record, release: bought + day), end, "A check that is late")
        XCTAssertNil(UpdateWindow.sparkleWindowEnd(record: record, release: end + day), "A key that does not cover this build")
        record.purchased = nil
        XCTAssertNil(UpdateWindow.sparkleWindowEnd(record: record, release: bought + day), "No purchase date yet")
        record.purchased = bought
        record.activationID = nil
        XCTAssertNil(UpdateWindow.sparkleWindowEnd(record: record, release: bought + day), "No activation: every update")
    }
}
