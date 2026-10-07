import XCTest

private struct FakeError: Error {}

/// What the service and the helper were asked, in order.
private final class Journal {
    var entries: [String] = []
}

/// "Operation not permitted" as ServiceManagement gives it.
private let notPermitted = NSError(domain: "SMAppServiceErrorDomain", code: 1)
private let signingFailed = NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionCodeSigningRequirementFailure)

private final class FakeService: HelperServiceManaging {
    var status: HelperStatus
    var statusAfterRegister: HelperStatus = .enabled
    var registerError: Error?
    /// Thrown by the next calls of register(), one each, and nothing is registered.
    var registerFailures: [Error] = []
    var registerAlwaysFails: Error?
    /// How long the system takes to drop the registration, and to enable a new one.
    var removalTime: TimeInterval = 0
    var enableTime: TimeInterval = 0
    var unregistered = false
    var registrations = 0
    var openedSettings = false
    var journal: Journal?
    var onUnregister: () -> Void = {}
    var onRegistered: () -> Void = {}
    private var pending: (left: TimeInterval, status: HelperStatus)?

    init(status: HelperStatus) { self.status = status }

    /// Time passes: the sleeper of the test calls this.
    func advance(by seconds: TimeInterval) {
        guard var waiting = pending else { return }
        waiting.left -= seconds
        pending = waiting
        if waiting.left <= 0 {
            status = waiting.status
            pending = nil
        }
    }

    private func change(to next: HelperStatus, after time: TimeInterval) {
        if time > 0 { pending = (time, next) } else { status = next }
    }

    func register() throws {
        registrations += 1
        journal?.entries.append("register")
        if !registerFailures.isEmpty { throw registerFailures.removeFirst() }
        if let registerAlwaysFails { throw registerAlwaysFails }
        change(to: statusAfterRegister, after: enableTime)
        onRegistered()
        if let registerError { throw registerError }
    }

    func unregister() async throws {
        unregistered = true
        journal?.entries.append("unregister")
        onUnregister()
        change(to: .notRegistered, after: removalTime)
    }

    func openLoginItemsSettings() { openedSettings = true }
}

// Stands in for the XPC proxy and the helper behind it.
private final class FakeHelper: SleepFlagHelperConnecting {
    var flag = false
    var setByHelper = false
    var unreachable = false
    /// What a call throws while the helper is unreachable.
    var error: Error = FakeError()
    /// Thrown by the next calls, one each, before anything else.
    var failures: [Error] = []
    /// A helper from a bundle that was replaced: it does what it is asked,
    /// and the app refuses its answer.
    var stale = false
    var clearFails = false
    /// A helper that answers and does not set the flag.
    var setFails = false
    /// The next set waits here until the test lets it go.
    var holdsNextSet = false
    var held: CheckedContinuation<Void, Never>?
    var calls: [String] = []
    var reconnects = 0
    var journal: Journal?
    var lostHandler: (() -> Void)?

    func onConnectionLost(_ handler: @escaping () -> Void) { lostHandler = handler }

    func reconnect() {
        reconnects += 1
        journal?.entries.append("reconnect")
    }

    private func called(_ name: String) {
        calls.append(name)
        journal?.entries.append(name)
    }

    private func fail() throws {
        if !failures.isEmpty { throw failures.removeFirst() }
        if unreachable { throw error }
    }

    func setSleepDisabled(_ on: Bool) async throws -> Bool {
        called("set \(on)")
        if holdsNextSet {
            holdsNextSet = false
            await withCheckedContinuation { held = $0 }
        }
        try fail()
        if on ? !setFails : !clearFails {
            flag = on
            setByHelper = on
        }
        if stale { throw signingFailed }
        return flag
    }

    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) {
        called("status")
        try fail()
        if stale { throw signingFailed }
        return (flag, setByHelper, "1.0 (1)")
    }

    func heartbeat() async throws -> Bool {
        called("heartbeat")
        try fail()
        if stale { throw signingFailed }
        return flag
    }
}

private final class FakeSudoers: SudoersCleaning {
    var entryExists: Bool

    init(entryExists: Bool = false) { self.entryExists = entryExists }

    func remove() async throws { entryExists = false }
}

@MainActor
final class SleepFlagControllerTests: XCTestCase {
    private var now: TimeInterval = 1_000
    private var slept: [TimeInterval] = []
    private var journal = Journal()
    /// Runs in every wait of the repair.
    private var whileWaiting: () -> Void = {}
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "SleepFlagControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeController(
        _ service: FakeService,
        _ helper: FakeHelper = FakeHelper(),
        _ sudoers: FakeSudoers = FakeSudoers()
    ) -> SleepFlagController {
        service.journal = journal
        helper.journal = journal
        // An hour, so the timer never fires in a test; heartbeats are sent by hand.
        // No wait is real: the sleeper moves the clock and the service.
        return SleepFlagController(
            service: service, helper: helper, sudoers: sudoers, heartbeatInterval: 3600, defaults: defaults,
            now: { self.now },
            sleep: { seconds in
                self.now += seconds
                self.slept.append(seconds)
                self.journal.entries.append("sleep \(seconds)")
                service.advance(by: seconds)
                self.whileWaiting()
            }
        )
    }

    /// A stale helper and the service that stops and starts it.
    private func staleHelper(on service: FakeService) -> FakeHelper {
        let helper = FakeHelper()
        helper.stale = true
        // A helper that is stopped clears the flag it owns.
        service.onUnregister = {
            helper.flag = false
            helper.setByHelper = false
        }
        service.onRegistered = { helper.stale = false }
        return helper
    }

    /// A helper that gives no answer: the real connection ends such a call
    /// with this error.
    private func silentHelper() -> FakeHelper {
        let helper = FakeHelper()
        helper.unreachable = true
        helper.error = HelperCallError.timedOut
        return helper
    }

    func testInstallEnables() async throws {
        let service = FakeService(status: .notRegistered)
        let controller = makeController(service)
        XCTAssertEqual(controller.helperStatus, .notRegistered)
        try await controller.install()
        XCTAssertEqual(controller.helperStatus, .enabled)
    }

    func testInstallThatNeedsApproval() async {
        for registerError in [FakeError(), nil] as [Error?] {
            let service = FakeService(status: .notRegistered)
            service.statusAfterRegister = .requiresApproval
            service.registerError = registerError
            let controller = makeController(service)
            do {
                try await controller.install()
                XCTFail("install did not throw")
            } catch {
                XCTAssertEqual(error as? SleepFlagError, .requiresApproval)
            }
            XCTAssertEqual(controller.helperStatus, .requiresApproval)
            controller.openLoginItemsSettings()
            XCTAssertTrue(service.openedSettings)
        }
    }

    func testInstallFailurePassesTheErrorOn() async {
        let service = FakeService(status: .notRegistered)
        service.statusAfterRegister = .notFound
        service.registerError = FakeError()
        let controller = makeController(service)
        do {
            try await controller.install()
            XCTFail("install did not throw")
        } catch {
            XCTAssertTrue(error is FakeError)
        }
        XCTAssertEqual(controller.helperStatus, .notFound)
    }

    func testSetAndClear() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        let on = await controller.setSleepDisabled(true)
        XCTAssertTrue(on)
        XCTAssertTrue(controller.sleepDisabled)
        let off = await controller.setSleepDisabled(false)
        XCTAssertFalse(off)
        XCTAssertEqual(helper.calls, ["set true", "set false"])
    }

    func testSetWithoutHelperDoesNothing() async {
        let helper = FakeHelper()
        for status in [HelperStatus.notRegistered, .requiresApproval, .notFound] {
            let controller = makeController(FakeService(status: status), helper)
            let on = await controller.setSleepDisabled(true)
            XCTAssertFalse(on)
        }
        XCTAssertEqual(helper.calls, [])
    }

    func testUnreachableHelperKeepsLastConfirmedValue() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        helper.unreachable = true
        let off = await controller.setSleepDisabled(false)
        XCTAssertTrue(off)
    }

    func testHeartbeatOnlyWhileWanted() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls, [])
        _ = await controller.setSleepDisabled(true)
        await controller.sendHeartbeat()
        _ = await controller.setSleepDisabled(false)
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls, ["set true", "heartbeat", "set false"])
    }

    func testHeartbeatSetsFlagAgainAfterHelperRestart() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        helper.flag = false
        helper.setByHelper = false
        await controller.sendHeartbeat()
        XCTAssertTrue(helper.flag)
        XCTAssertTrue(controller.sleepDisabled)
        XCTAssertEqual(helper.calls, ["set true", "heartbeat", "set true"])
    }

    func testUninstallClearsFlagFirst() async throws {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        try await controller.uninstall()
        XCTAssertEqual(helper.calls, ["set true", "set false", "status"])
        XCTAssertFalse(helper.flag)
        XCTAssertTrue(service.unregistered)
        XCTAssertEqual(controller.helperStatus, .notRegistered)
        XCTAssertFalse(controller.sleepDisabled)
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls.count, 3)
    }

    func testUninstallStopsWhenFlagStaysOn() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        helper.clearFails = true
        do {
            try await controller.uninstall()
            XCTFail("uninstall did not throw")
        } catch {
            XCTAssertEqual(error as? SleepFlagError, .flagNotCleared)
        }
        XCTAssertFalse(service.unregistered)
        XCTAssertEqual(controller.helperStatus, .enabled)
    }

    func testUninstallStopsWhenHelperIsUnreachable() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.unreachable = true
        let controller = makeController(service, helper)
        do {
            try await controller.uninstall()
            XCTFail("uninstall did not throw")
        } catch {
            XCTAssertTrue(error is FakeError)
        }
        XCTAssertFalse(service.unregistered)
    }

    func testUninstallLeavesAForeignFlagAlone() async throws {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.flag = true
        helper.clearFails = true
        let controller = makeController(service, helper)
        try await controller.uninstall()
        XCTAssertTrue(helper.flag)
        XCTAssertTrue(service.unregistered)
    }

    func testSudoersCleanup() async throws {
        let sudoers = FakeSudoers(entryExists: true)
        let pending = makeController(FakeService(status: .notRegistered), FakeHelper(), sudoers)
        XCTAssertTrue(pending.needsSudoersCleanup)
        try await pending.removeSudoersEntry()
        XCTAssertFalse(pending.needsSudoersCleanup)
        XCTAssertFalse(sudoers.entryExists)
    }

    func testRequestSendsOnlyChanges() {
        var request = SleepFlagRequest()
        XCTAssertNil(request.next(wanted: true, helperEnabled: false, now: now))
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now), true)
        XCTAssertNil(request.next(wanted: true, helperEnabled: true, now: now))
        XCTAssertEqual(request.next(wanted: false, helperEnabled: true, now: now), false)
        XCTAssertNil(request.next(wanted: false, helperEnabled: true, now: now))
    }

    func testRequestSendsAgainAfterTheHelperWasOff() {
        var request = SleepFlagRequest()
        XCTAssertEqual(request.next(wanted: false, helperEnabled: true, now: now), false, "clears a flag an earlier run left on")
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now), true)
        XCTAssertNil(request.next(wanted: true, helperEnabled: false, now: now))
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now), true)
        XCTAssertNil(request.next(wanted: false, helperEnabled: false, now: now))
        XCTAssertEqual(request.next(wanted: false, helperEnabled: true, now: now), false)
    }

    func testRequestSendsAgainAfterAFailedCall() {
        var request = SleepFlagRequest()
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now), true)
        request.didFail(now: now)
        XCTAssertNil(request.next(wanted: true, helperEnabled: true, now: now + 14), "Not before the retry interval is over")
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now + 15), true)
        XCTAssertNil(request.next(wanted: true, helperEnabled: true, now: now + 16), "Sent, and no failure since")
        request.didFail(now: now + 16)
        XCTAssertEqual(request.next(wanted: false, helperEnabled: true, now: now + 17), false, "Another value does not wait")
    }

    func testRequestForgetsAFailureWhenTheHelperIsOff() {
        var request = SleepFlagRequest()
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now), true)
        request.didFail(now: now)
        XCTAssertNil(request.next(wanted: true, helperEnabled: false, now: now + 1))
        XCTAssertEqual(request.next(wanted: true, helperEnabled: true, now: now + 2), true)
    }

    func testFlagLeftOnWhenTheHelperIsSwitchedOff() async {
        let service = FakeService(status: .enabled)
        let controller = makeController(service)
        _ = await controller.setSleepDisabled(true)
        XCTAssertFalse(controller.flagLeftOn)
        service.status = .requiresApproval
        controller.refreshStatus()
        XCTAssertTrue(controller.flagLeftOn)
    }

    /// The decision drops the flag while System Settings no longer calls
    /// the helper enabled, and the helper still runs. The old code sent
    /// nothing and went on with the heartbeats, so the flag stayed on.
    func testStopWantingEndsTheHeartbeatsAndClearsTheFlagOfAHelperThatIsNotEnabled() async {
        for status in [HelperStatus.requiresApproval, .notRegistered, .notFound] {
            let service = FakeService(status: .enabled)
            let helper = FakeHelper()
            let controller = makeController(service, helper)
            _ = await controller.setSleepDisabled(true)
            service.status = status
            controller.refreshStatus()
            XCTAssertTrue(controller.flagLeftOn)
            await controller.stopWanting()?.value
            XCTAssertEqual(helper.calls, ["set true", "set false"], "\(status)")
            XCTAssertFalse(helper.flag)
            XCTAssertFalse(controller.sleepDisabled)
            XCTAssertFalse(controller.flagLeftOn)
            await controller.sendHeartbeat()
            XCTAssertEqual(helper.calls.count, 2, "No heartbeat keeps the flag on")
            XCTAssertNil(controller.stopWanting(), "Nothing is owed any more")
        }
    }

    func testStopWantingWithAHelperThatIsGoneTriesNoMoreOftenThanAHeartbeat() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        service.status = .notRegistered
        controller.refreshStatus()
        helper.unreachable = true
        await controller.stopWanting()?.value
        XCTAssertEqual(helper.calls, ["set true", "set false"])
        XCTAssertTrue(controller.flagLeftOn, "Not confirmed, so the menu still says it")
        XCTAssertNil(controller.stopWanting())
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls.count, 2)
        now += 3600
        helper.unreachable = false
        await controller.stopWanting()?.value
        XCTAssertEqual(helper.calls.count, 3)
        XCTAssertFalse(controller.flagLeftOn)
    }

    func testStopWantingLeavesAnEnabledHelperToTheRequest() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        XCTAssertNil(controller.stopWanting())
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls, ["set true"], "The heartbeats stopped, and the request sends off")
        _ = await controller.setSleepDisabled(false)
        XCTAssertEqual(helper.calls, ["set true", "set false"])
    }

    func testClearForQuit() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        controller.clearForQuit(timeout: 2)
        XCTAssertFalse(helper.flag)
        XCTAssertEqual(helper.calls, ["set true", "set false"])
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls.count, 2, "no heartbeat after the clear")
    }

    func testClearForQuitMakesNoCallWithoutAFlag() {
        let helper = FakeHelper()
        makeController(FakeService(status: .enabled), helper).clearForQuit(timeout: 2)
        XCTAssertEqual(helper.calls, [])
    }

    func testOutdatedHelperIsRegisteredAgain() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertFalse(service.unregistered)
        XCTAssertEqual(service.registrations, 0)
        await controller.replaceHelper(ifNot: "1.1 (2)")
        XCTAssertTrue(service.unregistered)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(controller.helperStatus, .enabled)
    }

    func testHelperThatIsNotEnabledIsNotReplaced() async {
        let service = FakeService(status: .notRegistered)
        let helper = FakeHelper()
        await makeController(service, helper).replaceHelper(ifNot: "1.1 (2)")
        XCTAssertEqual(helper.calls, [])
        XCTAssertEqual(service.registrations, 0)
    }

    // MARK: A helper that gives no answer

    func testAHelperThatGivesNoVersionIsRegisteredAgainOnce() async {
        let service = FakeService(status: .enabled)
        let helper = silentHelper()
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertTrue(service.unregistered)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertTrue(controller.repairTried)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(service.registrations, 1, "Once in a launch")
    }

    func testAHelperThatGivesItsVersionOnANewConnectionIsLeftAlone() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.failures = [FakeError()]
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(helper.reconnects, 1)
        XCTAssertEqual(helper.calls, ["status", "status", "set false"], "The wanted value goes over the new connection")
        XCTAssertFalse(service.unregistered)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(controller.setup, .ready)
    }

    func testAnOutdatedHelperOnANewConnectionIsRegisteredAgain() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.failures = [FakeError()]
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.1 (2)")
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(helper.calls, ["status", "status", "set false", "status", "set false"], "The wanted value goes to the new helper")
    }

    func testAHelperThatWentAwayIsAskedForItsVersionAgain() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.failures = [HelperCallError.connectionLost]
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(helper.calls, ["status", "status"])
        XCTAssertEqual(service.registrations, 0, "launchd started it again, and it is the right one")
        XCTAssertFalse(controller.repairTried)
    }

    func testTheOutdatedHelperGetsTheWantedValueAfterItWasReplaced() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        await controller.replaceHelper(ifNot: "1.1 (2)")
        XCTAssertEqual(helper.calls, ["set true", "status", "set false", "status", "set true"])
        XCTAssertTrue(controller.sleepDisabled)
        XCTAssertFalse(controller.repairTried, "Another version is no failure")
    }

    func testSetIsTriedAgainAtOnceWhenTheHelperWentAway() async {
        let helper = FakeHelper()
        helper.failures = [HelperCallError.connectionLost]
        let controller = makeController(FakeService(status: .enabled), helper)
        let on = await controller.setSleepDisabled(true)
        XCTAssertTrue(on)
        XCTAssertEqual(helper.calls, ["set true", "set true"])
        XCTAssertFalse(controller.lastSetFailed)
    }

    func testSetIsTriedAgainOnlyOnceInOneGo() async {
        let helper = FakeHelper()
        helper.unreachable = true
        helper.error = CocoaError(.xpcConnectionInterrupted)
        let controller = makeController(FakeService(status: .enabled), helper)
        let on = await controller.setSleepDisabled(true)
        XCTAssertFalse(on)
        XCTAssertEqual(helper.calls, ["set true", "set true"])
        XCTAssertTrue(controller.lastSetFailed)
    }

    func testHeartbeatSendsTheValueAgainAfterAFailedSet() async {
        let helper = silentHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        let on = await controller.setSleepDisabled(true)
        XCTAssertFalse(on)
        XCTAssertTrue(controller.lastSetFailed)
        helper.unreachable = false
        await controller.sendHeartbeat()
        XCTAssertEqual(helper.calls, ["set true", "heartbeat", "set true"])
        XCTAssertTrue(controller.sleepDisabled)
        XCTAssertFalse(controller.lastSetFailed)
    }

    func testTwoFailedTriesRegisterTheHelperAgainOnce() async {
        let service = FakeService(status: .enabled)
        let helper = silentHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        XCTAssertEqual(service.registrations, 0, "One failure can be a helper that starts again")
        await controller.sendHeartbeat()
        XCTAssertTrue(service.unregistered)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(helper.reconnects, 3, "Two for the old helper, one for the new")
        XCTAssertEqual(
            helper.calls, ["set true", "heartbeat", "set true", "status", "status", "status", "status", "status", "set true"],
            "Two tries on a new connection, three for the first answer of the new helper, and the value once more"
        )
        XCTAssertTrue(controller.notResponding, "A repair that did not help is told at once")
        XCTAssertEqual(controller.setup, .notResponding)
        for _ in 1...3 { await controller.sendHeartbeat() }
        XCTAssertEqual(service.registrations, 1, "Once in a launch")
    }

    func testRegisteringAgainBringsTheFlagBack() async {
        let service = FakeService(status: .enabled)
        let helper = silentHelper()
        // The set, the heartbeat, the set again, and two tries on a new connection.
        helper.failures = Array(repeating: HelperCallError.timedOut, count: 5)
        helper.unreachable = false
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        await controller.sendHeartbeat()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(controller.setup, .ready)
        XCTAssertTrue(controller.sleepDisabled)
        now += 60
        controller.refreshHealth()
        XCTAssertFalse(controller.notResponding)
    }

    func testARepairThatNeedsApprovalDoesNotLoop() async {
        let service = FakeService(status: .enabled)
        service.statusAfterRegister = .requiresApproval
        let helper = silentHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        await controller.sendHeartbeat()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(controller.helperStatus, .requiresApproval)
        let calls = helper.calls.count
        now += 60
        await controller.sendHeartbeat()
        _ = await controller.setSleepDisabled(true)
        await controller.repairHelper()
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(helper.calls.count, calls + 1, "Only the heartbeat: a helper that waits for approval gets no set")
        XCTAssertFalse(controller.notResponding, "The helper's state says what to do")
    }

    func testNotRespondingAfterTwentySecondsWithoutAnAnswer() async {
        let helper = silentHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        XCTAssertFalse(controller.notResponding, "A helper that starts again takes a moment")
        now += 19
        controller.refreshHealth()
        XCTAssertFalse(controller.notResponding)
        now += 1
        controller.refreshHealth()
        XCTAssertTrue(controller.notResponding)
        helper.unreachable = false
        await controller.sendHeartbeat()
        XCTAssertFalse(controller.notResponding)
        XCTAssertTrue(controller.sleepDisabled)
    }

    func testNotRespondingWhenTheFlagIsNotWhatWasAskedFor() async {
        let helper = FakeHelper()
        helper.setFails = true
        let controller = makeController(FakeService(status: .enabled), helper)
        _ = await controller.setSleepDisabled(true)
        now += 15
        await controller.sendHeartbeat()
        now += 15
        await controller.sendHeartbeat()
        XCTAssertTrue(controller.notResponding)
        XCTAssertFalse(controller.lastSetFailed, "The helper answered")
        helper.setFails = false
        await controller.sendHeartbeat()
        XCTAssertFalse(controller.notResponding)
    }

    func testAFlagOfSomeoneElseIsNoTrouble() async {
        let helper = FakeHelper()
        helper.flag = true
        helper.clearFails = true
        let controller = makeController(FakeService(status: .enabled), helper)
        let value = await controller.setSleepDisabled(false)
        XCTAssertTrue(value)
        now += 60
        controller.refreshHealth()
        XCTAssertFalse(controller.notResponding)
    }

    func testAHelperThatWasSwitchedOffIsNotCalledNotResponding() async {
        let service = FakeService(status: .enabled)
        let controller = makeController(service, silentHelper())
        _ = await controller.setSleepDisabled(true)
        now += 30
        controller.refreshHealth()
        XCTAssertTrue(controller.notResponding)
        service.status = .requiresApproval
        controller.refreshStatus()
        XCTAssertFalse(controller.notResponding)
    }

    func testOnlyOneCallAtATime() async {
        let helper = FakeHelper()
        helper.holdsNextSet = true
        let controller = makeController(FakeService(status: .enabled), helper)
        let first = Task { await controller.setSleepDisabled(true) }
        while helper.held == nil { await Task.yield() }
        _ = await controller.setSleepDisabled(false)
        await controller.sendHeartbeat()
        await controller.connectionLost()
        XCTAssertEqual(helper.calls, ["set true"], "Nothing more while the call is under way")
        helper.held?.resume()
        _ = await first.value
        XCTAssertEqual(helper.calls, ["set true", "set false"], "The value that came later is sent after it")
        XCTAssertFalse(controller.sleepDisabled)
    }

    func testALostConnectionSendsTheWantedValueAtOnce() async {
        let helper = FakeHelper()
        let controller = makeController(FakeService(status: .enabled), helper)
        XCTAssertNotNil(helper.lostHandler)
        await controller.connectionLost()
        XCTAssertEqual(helper.calls, [], "Nothing is wanted")
        _ = await controller.setSleepDisabled(true)
        // The helper started again and cleared the flag of the one before it.
        helper.flag = false
        await controller.connectionLost()
        XCTAssertEqual(helper.calls, ["set true", "set true"])
        XCTAssertTrue(helper.flag)
        await controller.connectionLost()
        XCTAssertEqual(helper.calls.count, 2, "Not again before the next heartbeat would come")
        now += 3600
        await controller.connectionLost()
        XCTAssertEqual(helper.calls.count, 3)
    }

    func testTryAgainLeavesAHelperThatAnswersAlone() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        helper.flag = false
        await controller.repairHelper()
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(helper.calls, ["set true", "status", "set true"])
        XCTAssertTrue(helper.flag)
        XCTAssertTrue(controller.repairTried)
    }

    func testTryAgainRegistersAHelperThatGivesNoAnswer() async {
        let service = FakeService(status: .enabled)
        let helper = silentHelper()
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        await controller.sendHeartbeat()
        XCTAssertEqual(service.registrations, 1, "The repair of this launch")
        helper.unreachable = false
        helper.failures = [HelperCallError.timedOut, HelperCallError.timedOut]
        await controller.repairHelper()
        XCTAssertEqual(service.registrations, 2, "The user can ask as often as they like")
        XCTAssertTrue(controller.sleepDisabled)
    }

    // MARK: The repair

    /// The log of 2026-10-06: the app was replaced, the helper of the old
    /// bundle still ran, and register() right after unregister() was not
    /// permitted.
    func testAStaleHelperIsStartedAgainFromTheLog() async {
        let service = FakeService(status: .enabled)
        service.removalTime = 0.5
        service.registerFailures = [notPermitted, notPermitted]
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        var seen: Set<HelperSetup> = []
        whileWaiting = { seen.insert(controller.setup) }

        let on = await controller.setSleepDisabled(true)

        XCTAssertEqual(journal.entries, [
            "set true", "reconnect", "status",
            "unregister", "sleep 0.25", "sleep 0.25",
            "register", "sleep 0.5", "register", "sleep 1.0", "register",
            "reconnect", "status", "set true",
        ])
        XCTAssertTrue(on)
        XCTAssertTrue(helper.flag)
        XCTAssertFalse(controller.flagUnconfirmed)
        XCTAssertEqual(controller.helperStatus, .enabled)
        XCTAssertEqual(seen, [.repairing], "Never the hint of the first time")
        XCTAssertEqual(controller.setup, .ready)
        XCTAssertFalse(controller.notResponding)
    }

    func testAStaleHelperAtLaunchIsStartedAgain() async {
        let service = FakeService(status: .enabled)
        service.registerFailures = [notPermitted]
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(journal.entries, ["status", "reconnect", "status", "unregister", "register", "sleep 0.5", "register", "reconnect", "status", "set false"])
        XCTAssertEqual(controller.setup, .ready)
    }

    func testASetWhoseAnswerIsLostIsNotTakenForOff() async {
        let helper = FakeHelper()
        helper.failures = [HelperCallError.timedOut]
        let controller = makeController(FakeService(status: .enabled), helper)
        let on = await controller.setSleepDisabled(true)
        XCTAssertFalse(on)
        XCTAssertTrue(controller.flagUnconfirmed, "The helper may have set it")
        await controller.sendHeartbeat()
        XCTAssertFalse(controller.flagUnconfirmed)
        XCTAssertTrue(controller.sleepDisabled)
    }

    func testTheStoppedHelperClearsAFlagItSetWithoutAnAnswer() async {
        let service = FakeService(status: .enabled)
        service.registerAlwaysFails = notPermitted
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        XCTAssertEqual(helper.calls.first, "set true", "The stale helper did what it was asked")
        XCTAssertFalse(helper.flag, "And cleared it when it was stopped")
        XCTAssertFalse(controller.sleepDisabled)
    }

    func testRegisterIsTriedAgainOnlyWhenItWasNotPermitted() async {
        let service = FakeService(status: .enabled)
        service.registerFailures = [FakeError()]
        let controller = makeController(service, silentHelper())
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(slept, [])
        XCTAssertEqual(controller.setup, .notResponding)
    }

    func testARepairThatCannotRegisterTellsItAndTriesAgainLater() async {
        let service = FakeService(status: .enabled)
        service.registerAlwaysFails = notPermitted
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        XCTAssertEqual(service.registrations, 5)
        XCTAssertEqual(slept, [0.5, 1, 2, 4])
        XCTAssertEqual(controller.helperStatus, .notRegistered)
        XCTAssertEqual(controller.setup, .notResponding, "Not the hint of the first time")
        XCTAssertTrue(controller.repairTried, "Open System Settings is offered")

        XCTAssertFalse(controller.repairIsDue)
        await controller.retryRepairIfDue()
        XCTAssertEqual(service.registrations, 5, "Not before a minute is over")

        now += 60
        service.registerAlwaysFails = nil
        XCTAssertTrue(controller.repairIsDue)
        await controller.retryRepairIfDue()
        XCTAssertEqual(service.registrations, 6)
        XCTAssertEqual(controller.setup, .ready)
        XCTAssertTrue(helper.flag, "The wanted value goes to the new helper")
        XCTAssertFalse(controller.repairIsDue)
    }

    func testAfterTheLastTryTheUserIsAskedToSetUpAgain() async {
        let service = FakeService(status: .enabled)
        service.registerAlwaysFails = notPermitted
        let controller = makeController(service, staleHelper(on: service))
        _ = await controller.setSleepDisabled(true)
        for _ in 1...HelperRepair.slowRetries {
            XCTAssertEqual(controller.setup, .notResponding)
            now += 60
            await controller.retryRepairIfDue()
        }
        XCTAssertEqual(service.registrations, 5 * (1 + HelperRepair.slowRetries))
        XCTAssertEqual(controller.setup, .lost)
        now += 600
        XCTAssertFalse(controller.repairIsDue, "So many times in a launch")
    }

    func testTryAgainRegistersAHelperTheRepairTookAway() async {
        let service = FakeService(status: .enabled)
        service.registerAlwaysFails = notPermitted
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        service.registerAlwaysFails = nil
        await controller.repairHelper()
        XCTAssertEqual(controller.setup, .ready)
        XCTAssertTrue(helper.flag)
    }

    func testTryAgainSetsUpNoHelperThatWasNeverThere() async {
        let service = FakeService(status: .notRegistered)
        let controller = makeController(service)
        await controller.repairHelper()
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(controller.setup, .notSetUp)
    }

    func testARepairThatEndsInApprovalSaysSo() async {
        let service = FakeService(status: .enabled)
        service.statusAfterRegister = .requiresApproval
        service.registerError = notPermitted
        let controller = makeController(service, staleHelper(on: service))
        _ = await controller.setSleepDisabled(true)
        XCTAssertEqual(service.registrations, 1, "Waiting does not allow it")
        XCTAssertEqual(controller.setup, .requiresApproval)
        now += 60
        XCTAssertFalse(controller.repairIsDue)
    }

    func testTheNewHelperIsWaitedFor() async {
        let service = FakeService(status: .enabled)
        service.enableTime = 0.5
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        // The first answer of the new helper is late.
        service.onRegistered = {
            helper.stale = false
            helper.failures = [HelperCallError.connectionLost]
        }
        let on = await controller.setSleepDisabled(true)
        XCTAssertTrue(on)
        XCTAssertEqual(slept, [0.25, 0.25, 1])
        XCTAssertEqual(controller.setup, .ready)
    }

    func testNothingIsSentToTheHelperWhileItIsRepaired() async {
        let service = FakeService(status: .enabled)
        service.registerFailures = [notPermitted]
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        var asked = false
        whileWaiting = {
            guard !asked else { return }
            asked = true
            Task { @MainActor in
                await controller.sendHeartbeat()
                await controller.connectionLost()
                await controller.repairHelper()
            }
        }
        _ = await controller.setSleepDisabled(true)
        XCTAssertEqual(service.registrations, 2)
        XCTAssertFalse(helper.calls.contains("heartbeat"))
    }

    func testTheHelperThatWasSetUpIsRemembered() async throws {
        let service = FakeService(status: .notRegistered)
        let first = makeController(service)
        XCTAssertEqual(first.setup, .notSetUp)
        XCTAssertFalse(first.wasSetUp)
        try await first.install()
        XCTAssertEqual(first.setup, .ready)
        XCTAssertTrue(first.wasSetUp)

        // The next launch finds it gone.
        let later = makeController(FakeService(status: .notRegistered))
        XCTAssertEqual(later.setup, .lost)
        let waiting = makeController(FakeService(status: .requiresApproval))
        XCTAssertEqual(waiting.setup, .requiresApproval)
        XCTAssertTrue(waiting.wasSetUp)

        try await first.uninstall()
        XCTAssertFalse(first.wasSetUp, "The user removed it")
        XCTAssertEqual(first.setup, .notSetUp)
    }

    func testNoOffIsSentAfterTheHelperIsSetUpWhileTheMacIsHeld() async throws {
        let service = FakeService(status: .enabled)
        service.registerAlwaysFails = notPermitted
        let helper = staleHelper(on: service)
        let controller = makeController(service, helper)
        var request = SleepFlagRequest()
        // The aggregator's part: the decision asks for the flag all the time.
        func sync() async {
            guard let value = request.next(wanted: true, helperEnabled: controller.helperStatus == .enabled, now: now) else { return }
            _ = await controller.setSleepDisabled(value)
            if controller.lastSetFailed { request.didFail(now: now) }
        }
        await sync()
        XCTAssertEqual(controller.helperStatus, .notRegistered, "The repair lost the helper")
        await sync()

        service.registerAlwaysFails = nil
        try await controller.install()
        let before = helper.calls.count
        for _ in 1...4 {
            await sync()
            now += 15
            await controller.sendHeartbeat()
            controller.refreshStatus()
            await controller.retryRepairIfDue()
            await controller.connectionLost()
        }
        let after = Array(helper.calls.dropFirst(before))
        XCTAssertEqual(after.first, "set true")
        XCTAssertFalse(after.contains("set false"), "\(after)")
        XCTAssertFalse(after.contains("status"), "The helper is not repaired: \(after)")
        XCTAssertTrue(helper.flag)
    }

    func testWhichErrorsMeanNotPermittedAndStale() {
        XCTAssertTrue(HelperRepair.isNotPermitted(notPermitted))
        XCTAssertTrue(HelperRepair.isNotPermitted(POSIXError(.EPERM)))
        XCTAssertFalse(HelperRepair.isNotPermitted(NSError(domain: "SMAppServiceErrorDomain", code: 3)))
        XCTAssertFalse(HelperRepair.isNotPermitted(FakeError()))
        XCTAssertTrue(HelperCall.isSigningFailure(NSError(domain: NSCocoaErrorDomain, code: 4102)))
        XCTAssertFalse(HelperCall.isSigningFailure(HelperCallError.timedOut))
        XCTAssertFalse(HelperCall.isConnectionLoss(signingFailed))
    }

    func testRepairIsTakenOnce() {
        var health = HelperHealth()
        XCTAssertFalse(health.takeRepair())
        health.failed(now: 0)
        XCTAssertFalse(health.takeRepair())
        health.failed(now: 15)
        XCTAssertTrue(health.takeRepair())
        health.failed(now: 30)
        XCTAssertFalse(health.takeRepair())
        var fresh = HelperHealth()
        XCTAssertTrue(fresh.takeRepair(atOnce: true))
        XCTAssertFalse(fresh.takeRepair(atOnce: true))
        var answered = HelperHealth()
        answered.failed(now: 0)
        answered.answered(confirmed: true, wanted: true, now: 1)
        answered.failed(now: 2)
        XCTAssertFalse(answered.takeRepair(), "Two in a row, not two in all")
    }
}
