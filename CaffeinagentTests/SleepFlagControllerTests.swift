import XCTest

private struct FakeError: Error {}

private final class FakeService: HelperServiceManaging {
    var status: HelperStatus
    var statusAfterRegister: HelperStatus = .enabled
    var registerError: Error?
    var unregistered = false
    var openedSettings = false

    init(status: HelperStatus) { self.status = status }

    func register() throws {
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
    var clearFails = false
    var calls: [String] = []

    func setSleepDisabled(_ on: Bool) async throws -> Bool {
        calls.append("set \(on)")
        if unreachable { throw FakeError() }
        if on || !clearFails {
            flag = on
            setByHelper = on
        }
        return flag
    }

    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) {
        calls.append("status")
        if unreachable { throw FakeError() }
        return (flag, setByHelper, "1.0 (1)")
    }

    func heartbeat() async throws -> Bool {
        calls.append("heartbeat")
        if unreachable { throw FakeError() }
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
    private func makeController(
        _ service: FakeService,
        _ helper: FakeHelper = FakeHelper(),
        _ sudoers: FakeSudoers = FakeSudoers()
    ) -> SleepFlagController {
        // An hour, so the timer never fires in a test; heartbeats are sent by hand.
        SleepFlagController(service: service, helper: helper, sudoers: sudoers, heartbeatInterval: 3600)
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
        XCTAssertFalse(pending.needsSudoersCleanup)
        try await pending.install()
        XCTAssertTrue(pending.needsSudoersCleanup)
        try await pending.removeSudoersEntry()
        XCTAssertFalse(pending.needsSudoersCleanup)
        XCTAssertFalse(sudoers.entryExists)
    }
}
