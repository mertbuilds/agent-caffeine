import XCTest

@MainActor
final class LicenseManagerTests: XCTestCase {
    private let key = "AGENTCAF-3F2C1D0E-8B7A-4C6D-9E5F-1A2B3C4D5E6F"
    private let day = LicenseRules.day
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private var api: StubLicenseAPI!
    private var store: MemoryLicenseStore!
    private var defaults: UserDefaults!
    private var now: Date!
    /// Seconds on the clock that counts during sleep and ignores the wall clock.
    private var uptime: TimeInterval = 0

    override func setUp() async throws {
        api = StubLicenseAPI()
        store = MemoryLicenseStore()
        defaults = TestDefaults()
        now = t0
        uptime = 0
    }

    private func makeManager() -> LicenseManager {
        LicenseManager(client: api, store: store, defaults: defaults, label: "Mac14,2", now: { [unowned self] in self.now }, uptime: { [unowned self] in self.uptime })
    }

    func testFirstLaunchStartsTheTrial() {
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 7))
        XCTAssertEqual(store.record?.trialStart, t0)
        now = t0 + 5 * day
        manager.tick()
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 2))
        now = t0 + 7 * day
        manager.tick()
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
    }

    func testActivateSuccess() async {
        let manager = makeManager()
        api.activation = .activated(id: "act-1")
        await manager.activate(key: " \(key)\n")
        XCTAssertEqual(manager.entitlement, .licensed)
        XCTAssertNil(manager.message)
        XCTAssertEqual(api.activateLabels, ["Mac14,2"])
        XCTAssertEqual(store.record?.key, key)
        XCTAssertEqual(store.record?.activationID, "act-1")
        XCTAssertEqual(store.record?.lastValidated, t0)
    }

    /// The plan of the key and the end of the trial, for Settings.
    func testTheActivationSaysOnHowManyMacsTheKeyRuns() async {
        let manager = makeManager()
        XCTAssertEqual(manager.trialEnd, t0 + LicenseRules.trialLength)
        api.activation = .activated(id: "act-1", macs: 3)
        await manager.activate(key: key)
        XCTAssertEqual(store.record?.macLimit, 3)
        XCTAssertEqual(PanelText.keyRunsOn(macs: 3), "This key runs on 3 Macs.")
        XCTAssertEqual(PanelText.keyRunsOn(macs: 1), "This key runs on 1 Mac.")
        XCTAssertEqual(
            LicenseMessage.limitReached.text,
            "This key is in use on as many Macs as it allows. Choose Deactivate this Mac on one of them, or remove one in Manage in Polar, then try again."
        )
    }

    func testActivateLimitReached() async {
        let manager = makeManager()
        api.activation = .limitReached
        await manager.activate(key: key)
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 7))
        XCTAssertEqual(manager.message, .limitReached)
        XCTAssertNil(store.record?.activationID)
    }

    func testExpiredTrialThenActivationIsLicensed() async {
        store.record = LicenseRecord(trialStart: t0 - 10 * day, latestSeen: t0 - day)
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
        api.activation = .activated(id: "act-1")
        await manager.activate(key: key)
        XCTAssertEqual(manager.entitlement, .licensed)
    }

    func testValidateTurnsLicensedMacUnlicensedWhenActivationIsGone() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0 - day, trialStart: t0 - 20 * day)
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .licensed)
        api.validation = .notFound
        await manager.validate()
        XCTAssertEqual(api.validateIDs, ["act-1"])
        XCTAssertEqual(manager.entitlement, .expired(.activationRemoved))
        XCTAssertEqual(manager.message, .activationGone)
        XCTAssertNil(store.record?.activationID)
        XCTAssertNil(store.record?.lastValidated)
        XCTAssertEqual(store.record?.key, key, "The key text stays for a one-click activation")
    }

    func testValidateRevokedFallsBackToTrial() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 2 * day)
        let manager = makeManager()
        api.validation = .revoked
        await manager.validate()
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 5))
        XCTAssertEqual(manager.message, .revoked)
        XCTAssertNil(store.record?.activationID)
    }

    func testOfflineKeepsLicensedForThirtyDaysThenNot() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        let manager = makeManager()
        api.validation = .unavailable
        now = t0 + 29 * day
        await manager.validate()
        XCTAssertEqual(manager.entitlement, .licensed)
        XCTAssertNil(manager.message)
        now = t0 + 31 * day
        await manager.validate()
        XCTAssertEqual(manager.entitlement, .expired(.unverified))
        XCTAssertEqual(store.record?.activationID, "act-1", "Could not ask never forgets the activation")
        api.validation = .valid()
        await manager.validate()
        XCTAssertEqual(manager.entitlement, .licensed)
        XCTAssertEqual(store.record?.lastValidated, t0 + 31 * day)
    }

    func testDeactivateFreesTheState() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        let manager = makeManager()
        api.deactivation = .unavailable
        await manager.deactivate()
        XCTAssertEqual(manager.entitlement, .licensed)
        XCTAssertEqual(manager.message, .unavailable)
        api.deactivation = .deactivated
        await manager.deactivate()
        XCTAssertEqual(api.deactivateIDs, ["act-1", "act-1"])
        XCTAssertEqual(manager.entitlement, .expired(.activationRemoved))
        XCTAssertNil(manager.message)
        XCTAssertNil(store.record?.activationID)
        XCTAssertNil(store.record?.lastValidated)
    }

    func testActivatingTheSameKeyAgainValidatesFirst() async {
        // Offline past the grace: the activation is still this Mac's.
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0 - 40 * day, trialStart: t0 - 40 * day)
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .expired(.unverified))
        api.validation = .valid()
        await manager.activate(key: key)
        XCTAssertEqual(manager.entitlement, .licensed)
        XCTAssertTrue(api.activateLabels.isEmpty)
    }

    func testReinstallKeepsTheTrialClock() {
        // Preferences deleted, Keychain kept.
        store.record = LicenseRecord(trialStart: t0 - 8 * day, latestSeen: t0 - day)
        XCTAssertEqual(makeManager().entitlement, .expired(.trialOver))
        // Keychain item deleted, preferences kept.
        store.record = nil
        XCTAssertEqual(makeManager().entitlement, .expired(.trialOver))
    }

    func testClockSetBackDoesNotRestoreTheTrial() {
        let manager = makeManager()
        now = t0 + 8 * day
        manager.tick()
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
        now = t0
        manager.tick()
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
    }

    func testUnreadableKeychainFallsBackToTheMirror() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        _ = makeManager()
        XCTAssertEqual(defaults.object(forKey: "License.lastValidated") as? Date, t0)

        store.failLoad = true
        store.saves = 0
        now = t0 + 2 * day
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .licensed, "A paying user is not locked out at once")
        XCTAssertNotNil(manager.storageError)
        XCTAssertEqual(store.saves, 0, "An unreadable record is never written over")
        await manager.validate()
        XCTAssertTrue(api.validateIDs.isEmpty)

        now = t0 + 31 * day
        _ = await manager.tick()?.value
        XCTAssertEqual(manager.entitlement, .expired(.unverified))

        store.failLoad = false
        _ = await manager.tick()?.value
        XCTAssertNil(manager.storageError)
        XCTAssertEqual(manager.record.activationID, "act-1")
    }

    // MARK: Clock set back while the app runs

    /// Advances the measured clock a day at a time, with the wall clock
    /// standing still where it was set back to.
    private func runDays(_ days: Int, _ manager: LicenseManager) async {
        for _ in 0..<days {
            uptime += day
            _ = await manager.tick()?.value
        }
    }

    func testClockSetBackMidTrialStillExpiresOnSchedule() async {
        let manager = makeManager()
        await runDays(2, manager)
        now = t0 + 2 * day
        manager.tick()
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 5))
        now = t0 - 28 * day
        await runDays(4, manager)
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 1))
        await runDays(1, manager)
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
    }

    func testOfflineMacWithClockSetBackLeavesTheGraceAfterThirtyDays() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        api.validation = .unavailable
        let manager = makeManager()
        now = t0 - 60 * day
        await runDays(30, manager)
        XCTAssertEqual(manager.entitlement, .licensed)
        uptime += 1
        _ = await manager.tick()?.value
        XCTAssertEqual(manager.entitlement, .expired(.unverified))
    }

    func testForwardClockIsUnchanged() {
        let manager = makeManager()
        for _ in 0..<6 {
            uptime += day
            now += day
            manager.tick()
        }
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 1))
        XCTAssertEqual(manager.record.latestSeen, t0 + 6 * day)
        uptime += day - 1
        now += day - 1
        manager.tick()
        XCTAssertEqual(manager.entitlement, .trial(daysLeft: 1))
        uptime += 1
        now += 1
        manager.tick()
        XCTAssertEqual(manager.entitlement, .expired(.trialOver))
    }

    // MARK: Answers that arrive late

    func testLateAnswerAfterDeactivatingIsIgnored() async {
        for late in [LicenseValidation.valid(), .notFound] {
            store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0 - 40 * day, trialStart: t0 - 40 * day)
            let manager = makeManager()
            let gate = ValidationGate()
            api.validateGate = gate
            api.validation = late
            let pending = Task { await manager.validate() }
            await gate.waitForCaller()
            api.deactivation = .deactivated
            await manager.deactivate()
            await gate.open()
            let result = await pending.value
            XCTAssertNil(result, "\(late)")
            XCTAssertNil(manager.record.lastValidated, "\(late)")
            XCTAssertNil(manager.message, "\(late)")
            XCTAssertEqual(manager.entitlement, .expired(.activationRemoved), "\(late)")
            api.validateGate = nil
        }
    }

    func testLateAnswerAfterActivatingAnotherKeyIsIgnored() async {
        let otherKey = "AGENTCAF-00000000-0000-4000-8000-000000000002"
        for late in [LicenseValidation.valid(), .notFound] {
            store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0 - 40 * day, trialStart: t0 - 40 * day)
            now = t0
            let manager = makeManager()
            let gate = ValidationGate()
            api.validateGate = gate
            api.validation = late
            let pending = Task { await manager.validate() }
            await gate.waitForCaller()
            api.activation = .activated(id: "act-2")
            await manager.activate(key: otherKey)
            now = t0 + 3600
            await gate.open()
            let result = await pending.value
            XCTAssertNil(result, "\(late)")
            XCTAssertEqual(manager.record.key, otherKey, "\(late)")
            XCTAssertEqual(manager.record.activationID, "act-2", "\(late)")
            XCTAssertEqual(manager.record.lastValidated, t0, "\(late)")
            XCTAssertNil(manager.message, "\(late)")
            XCTAssertEqual(manager.entitlement, .licensed, "\(late)")
            api.validateGate = nil
        }
    }

    // MARK: Validation schedule

    func testBurstOfTicksAsksPolarOnce() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        let manager = makeManager()
        let gate = ValidationGate()
        api.validateGate = gate
        api.validation = .valid()
        let first = manager.tick()
        XCTAssertNotNil(first)
        for _ in 0..<10 {
            XCTAssertEqual(manager.tick(), first, "Before the first request starts")
        }
        await gate.waitForCaller()
        // A clock set back makes a validation due on every tick.
        now = t0 - day
        for _ in 0..<10 {
            XCTAssertEqual(manager.tick(), first, "While the first request waits for Polar")
        }
        let joined = Task { await manager.checkNow() }
        while !manager.busy { await Task.yield() }
        await gate.open()
        let result = await first?.value
        await joined.value
        XCTAssertEqual(result, .valid())
        XCTAssertEqual(api.validateIDs, ["act-1"])
        XCTAssertEqual(manager.entitlement, .licensed)
    }

    func testValidationSchedule() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0, trialStart: t0 - 20 * day)
        let manager = makeManager()
        XCTAssertTrue(manager.validationDue, "Nothing asked yet")

        api.validation = .valid()
        await manager.validate()
        now = t0 + 3600
        XCTAssertFalse(manager.validationDue, "Not an hour after a valid answer")
        now = t0 + day - 1
        XCTAssertFalse(manager.validationDue)
        now = t0 + day
        XCTAssertTrue(manager.validationDue, "Once a day")

        now = t0
        api.validation = .unavailable
        await manager.validate()
        now = t0 + 3600 - 1
        XCTAssertFalse(manager.validationDue)
        now = t0 + 3600
        XCTAssertTrue(manager.validationDue, "An hour after could not ask")

        now = t0
        api.validation = .valid()
        await manager.validate()
        now = t0 - 1
        XCTAssertTrue(manager.validationDue, "The clock went back")
    }

    // MARK: Expired reasons

    func testCheckNowRevalidatesAnUnverifiedMac() async {
        store.record = LicenseRecord(key: key, activationID: "act-1", lastValidated: t0 - 40 * day, trialStart: t0 - 40 * day)
        let manager = makeManager()
        XCTAssertEqual(manager.entitlement, .expired(.unverified))
        api.validation = .unavailable
        await manager.checkNow()
        XCTAssertEqual(manager.message, .unavailable)
        XCTAssertFalse(manager.busy)
        api.validation = .valid()
        await manager.checkNow()
        XCTAssertNil(manager.message)
        XCTAssertEqual(manager.entitlement, .licensed)
    }
}

/// Holds `validate` until the test opens it, so an answer can arrive after
/// the activation changed.
actor ValidationGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        await withCheckedContinuation { waiting.append($0) }
    }

    func waitForCaller() async {
        while waiting.isEmpty { await Task.yield() }
    }

    func open() {
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

@MainActor
final class StubLicenseAPI: LicenseAPI {
    var activation: LicenseActivation = .unavailable
    var validation: LicenseValidation = .unavailable
    var deactivation: LicenseDeactivation = .unavailable
    var validateGate: ValidationGate?
    private(set) var activateLabels: [String] = []
    private(set) var validateIDs: [String] = []
    private(set) var deactivateIDs: [String] = []

    func activate(key: String, label: String) async -> LicenseActivation {
        activateLabels.append(label)
        return activation
    }

    func validate(key: String, activationID: String) async -> LicenseValidation {
        validateIDs.append(activationID)
        let answer = validation
        await validateGate?.pass()
        return answer
    }

    func deactivate(key: String, activationID: String) async -> LicenseDeactivation {
        deactivateIDs.append(activationID)
        return deactivation
    }
}

final class MemoryLicenseStore: LicenseStore {
    var record: LicenseRecord?
    var failLoad = false
    var saves = 0

    func load() throws -> LicenseRecord? {
        if failLoad { throw LicenseStoreError(message: "The Keychain could not be used.") }
        return record
    }

    func save(_ record: LicenseRecord) throws {
        saves += 1
        self.record = record
    }
}
