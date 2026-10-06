import XCTest

private struct FakeError: Error {}

private final class FakeService: HelperServiceManaging {
    var status: HelperStatus
    var statusAfterRegister: HelperStatus = .enabled
    var registerError: Error?
    var unregistered = false
    var registrations = 0
    var openedSettings = false

    init(status: HelperStatus) { self.status = status }

    func register() throws {
        registrations += 1
        status = statusAfterRegister
        if let registerError { throw registerError }
    }

    func unregister() async throws {
        unregistered = true
        status = .notRegistered
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
    var clearFails = false
    /// A helper that answers and does not set the flag.
    var setFails = false
    /// The next set waits here until the test lets it go.
    var holdsNextSet = false
    var held: CheckedContinuation<Void, Never>?
    var calls: [String] = []
    var lostHandler: (() -> Void)?

    func onConnectionLost(_ handler: @escaping () -> Void) { lostHandler = handler }

    private func fail() throws {
        if !failures.isEmpty { throw failures.removeFirst() }
        if unreachable { throw error }
    }

    func setSleepDisabled(_ on: Bool) async throws -> Bool {
        calls.append("set \(on)")
        if holdsNextSet {
            holdsNextSet = false
            await withCheckedContinuation { held = $0 }
        }
        try fail()
        if on ? !setFails : !clearFails {
            flag = on
            setByHelper = on
        }
        return flag
    }

    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) {
        calls.append("status")
        try fail()
        return (flag, setByHelper, "1.0 (1)")
    }

    func heartbeat() async throws -> Bool {
        calls.append("heartbeat")
        try fail()
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

    private func makeController(
        _ service: FakeService,
        _ helper: FakeHelper = FakeHelper(),
        _ sudoers: FakeSudoers = FakeSudoers()
    ) -> SleepFlagController {
        // An hour, so the timer never fires in a test; heartbeats are sent by hand.
        SleepFlagController(service: service, helper: helper, sudoers: sudoers, heartbeatInterval: 3600, now: { self.now })
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

    func testAHelperThatThrowsOnItsVersionIsRegisteredAgain() async {
        let service = FakeService(status: .enabled)
        let helper = FakeHelper()
        helper.failures = [FakeError()]
        let controller = makeController(service, helper)
        await controller.replaceHelper(ifNot: "1.0 (1)")
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(helper.calls, ["status", "set false"], "The wanted value goes to the new helper")
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
        XCTAssertEqual(helper.calls, ["set true", "status", "set false", "set true"])
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
        XCTAssertEqual(helper.calls, ["set true", "heartbeat", "set true", "set true"], "The new helper gets the value at once")
        for _ in 1...3 { await controller.sendHeartbeat() }
        XCTAssertEqual(service.registrations, 1, "Once in a launch")
    }

    func testRegisteringAgainBringsTheFlagBack() async {
        let service = FakeService(status: .enabled)
        let helper = silentHelper()
        helper.failures = [HelperCallError.timedOut, HelperCallError.timedOut, HelperCallError.timedOut]
        helper.unreachable = false
        let controller = makeController(service, helper)
        _ = await controller.setSleepDisabled(true)
        await controller.sendHeartbeat()
        XCTAssertEqual(service.registrations, 1)
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
        helper.failures = [HelperCallError.timedOut]
        await controller.repairHelper()
        XCTAssertEqual(service.registrations, 2, "The user can ask as often as they like")
        XCTAssertTrue(controller.sleepDisabled)
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
