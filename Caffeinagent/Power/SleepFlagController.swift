import Foundation
import os

enum HelperStatus: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
}

enum SleepFlagError: LocalizedError, Equatable {
    case requiresApproval
    case flagNotCleared

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Allow agent caffeine in System Settings > General > Login Items."
        case .flagNotCleared:
            return "agent caffeine could not let your Mac sleep again, so the helper was not removed. Try again."
        }
    }
}

@MainActor
protocol SleepFlagControlling: AnyObject {
    var helperStatus: HelperStatus { get }
    var needsSudoersCleanup: Bool { get }
    // Throws SleepFlagError.requiresApproval when the user still has to allow
    // the helper; offer openLoginItemsSettings() then.
    func install() async throws
    func uninstall() async throws
    func openLoginItemsSettings()
    // Returns the value the helper confirmed.
    func setSleepDisabled(_ on: Bool) async -> Bool
    func removeSudoersEntry() async throws
}

// The registration of the helper with the system. SMAppService in the app.
protocol HelperServiceManaging {
    var status: HelperStatus { get }
    func register() throws
    func unregister() async throws
    func openLoginItemsSettings()
}

// The helper's XPC calls, as async functions. They throw when the helper
// cannot be reached or gives no answer in time, so none of them hangs.
protocol SleepFlagHelperConnecting {
    // The handler runs when the helper went away, on any thread.
    func onConnectionLost(_ handler: @escaping () -> Void)
    func setSleepDisabled(_ on: Bool) async throws -> Bool
    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String)
    func heartbeat() async throws -> Bool
}

// The sudoers entry of the method this helper replaced.
protocol SudoersCleaning {
    var entryExists: Bool { get }
    func remove() async throws
}

/// Which value to send to the helper, so it is called only on a change,
/// and again after a call that failed.
struct SleepFlagRequest: Equatable {
    /// A value that did not get through is sent again after this long.
    static let retryInterval: TimeInterval = 15

    private(set) var sent: Bool?
    private var failed: Bool?
    private var retryAt: TimeInterval = 0

    /// The value to send now, nil for no call. A helper that is not enabled
    /// gets no call. The next time it is enabled it gets the wanted value,
    /// also when that is off: the call then clears a flag that an earlier
    /// run left on.
    /// - Parameter now: seconds on a clock that only moves forward.
    mutating func next(wanted: Bool, helperEnabled: Bool, now: TimeInterval) -> Bool? {
        guard helperEnabled else {
            sent = nil
            failed = nil
            return nil
        }
        guard sent != wanted else { return nil }
        if failed == wanted, now < retryAt { return nil }
        sent = wanted
        failed = nil
        return wanted
    }

    /// The call for the value sent last did not get through. The same value
    /// is sent again after the retry interval, another one at once.
    mutating func didFail(now: TimeInterval) {
        guard let value = sent else { return }
        sent = nil
        failed = value
        retryAt = now + Self.retryInterval
    }
}

@MainActor
final class SleepFlagController: ObservableObject, SleepFlagControlling {
    @PublishedOnChange private(set) var helperStatus: HelperStatus
    // The last value the helper confirmed.
    @PublishedOnChange private(set) var sleepDisabled = false
    @PublishedOnChange private(set) var needsSudoersCleanup = false
    /// The helper is enabled in System Settings, and for some time it gave
    /// no answer or did not set the flag the app asked for.
    @PublishedOnChange private(set) var notResponding = false
    /// The helper was registered again in this launch.
    @PublishedOnChange private(set) var repairTried = false
    /// The last try to set the flag ended without an answer.
    private(set) var lastSetFailed = false

    private let service: HelperServiceManaging
    private let helper: SleepFlagHelperConnecting
    private let sudoers: SudoersCleaning
    private let heartbeatInterval: TimeInterval
    private let now: () -> TimeInterval
    private var health = HelperHealth()
    private var wanted = false
    private var sending = false
    private var sendAgain = false
    private var lastSendAfterLoss = -TimeInterval.infinity
    private var heartbeatTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "SleepFlagController")

    init(
        service: HelperServiceManaging,
        helper: SleepFlagHelperConnecting,
        sudoers: SudoersCleaning,
        heartbeatInterval: TimeInterval = SleepFlagHelper.heartbeatInterval,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.service = service
        self.helper = helper
        self.sudoers = sudoers
        self.heartbeatInterval = heartbeatInterval
        self.now = now
        self.helperStatus = service.status
        refreshStatus()
        helper.onConnectionLost { [weak self] in
            Task { @MainActor in await self?.connectionLost() }
        }
    }

    // The user can allow or remove the helper in System Settings at any time.
    func refreshStatus() {
        let status = service.status
        if helperStatus != status { helperStatus = status }
        let cleanup = sudoers.entryExists
        if needsSudoersCleanup != cleanup { needsSudoersCleanup = cleanup }
        refreshHealth()
    }

    /// Trouble with the helper shows only after it lasted a while, so this
    /// is called on a timer too.
    func refreshHealth() {
        if helperStatus != .enabled { health.helperIsOff() }
        let silent = health.notResponding(now: now())
        if notResponding != silent { notResponding = silent }
        if repairTried != health.repairTried { repairTried = health.repairTried }
    }

    func install() async throws {
        do {
            try service.register()
        } catch {
            refreshStatus()
            if helperStatus == .requiresApproval { throw SleepFlagError.requiresApproval }
            log.error("register failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        refreshStatus()
        if helperStatus == .requiresApproval { throw SleepFlagError.requiresApproval }
    }

    // Unregistering stops the helper and its watchdog with it, so a flag the
    // helper still holds would stay on for good. It is cleared first, and the
    // helper stays when that fails.
    func uninstall() async throws {
        wanted = false
        stopHeartbeat()
        refreshStatus()
        if helperStatus == .enabled {
            sleepDisabled = try await helper.setSleepDisabled(false)
            if try await helper.status().setByHelper { throw SleepFlagError.flagNotCleared }
        }
        try await service.unregister()
        refreshStatus()
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    /// The user switched the helper off in System Settings while the flag
    /// was on. Nothing clears the flag until the helper runs again.
    var flagLeftOn: Bool { helperStatus != .enabled && sleepDisabled }

    /// After an update the helper that runs can still be the old binary:
    /// launchd keeps the process it started. Registering again makes it
    /// start the new one. A helper that gives no version is registered
    /// again too, once in a launch. Not tested with a real update yet:
    /// check that the approval in Login Items survives it.
    func replaceHelper(ifNot appVersion: String) async {
        refreshStatus()
        guard helperStatus == .enabled else { return }
        do {
            let running = try await helperVersion()
            guard running != appVersion else { return }
            log.info("helper is \(running, privacy: .public), app is \(appVersion, privacy: .public): registering again")
            // So the helper that is stopped has no flag to clear on its way out.
            _ = try? await helper.setSleepDisabled(false)
        } catch {
            log.error("the helper gave no version: \(String(describing: error), privacy: .public)")
            health.failed(now: now())
            guard health.takeRepair(atOnce: true) else { return refreshHealth() }
        }
        await registerAgain()
        await send()
    }

    /// "Try again" in the menu and in Preferences. A helper that answers is
    /// left alone, one that does not is registered again. When that needs
    /// the user's approval, the helper's state says so.
    func repairHelper() async {
        refreshStatus()
        guard helperStatus == .enabled else { return }
        health.repairAsked()
        if (try? await helperVersion()) == nil { await registerAgain() }
        await send()
    }

    // A helper that went away while the call was under way was started
    // again by launchd for the second try.
    private func helperVersion() async throws -> String {
        do {
            return try await helper.status().version
        } catch where HelperCall.isConnectionLoss(error) {
            return try await helper.status().version
        }
    }

    // unregister() stops the helper, and a helper that is stopped clears a
    // flag it owns. True when the helper is enabled afterwards.
    @discardableResult
    private func registerAgain() async -> Bool {
        log.info("registering the helper again")
        do {
            try await service.unregister()
            try service.register()
        } catch {
            log.error("registering the helper again failed: \(error.localizedDescription, privacy: .public)")
        }
        // The flag went with the old helper, whatever a call under way says.
        sendAgain = sending
        refreshStatus()
        log.info("the helper is \(self.helperStatus == .enabled ? "enabled" : "not enabled", privacy: .public) after registering again")
        return helperStatus == .enabled
    }

    /// For quitting, where nothing can await: blocks the caller for at most
    /// `timeout` seconds. When the call is late or lost, the heartbeats
    /// have stopped and the helper's watchdog clears the flag.
    func clearForQuit(timeout: TimeInterval) {
        let owed = wanted || sleepDisabled
        wanted = false
        stopHeartbeat()
        guard owed, helperStatus == .enabled else { return }
        let done = DispatchSemaphore(value: 0)
        let helper = helper
        Task.detached {
            _ = try? await helper.setSleepDisabled(false)
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    func setSleepDisabled(_ on: Bool) async -> Bool {
        wanted = on
        if on { startHeartbeat() } else { stopHeartbeat() }
        await send()
        return sleepDisabled
    }

    /// Brings the helper to the wanted value. One call at a time: a value
    /// that changes while a call is under way is sent after it.
    private func send() async {
        guard !sending else { return }
        sending = true
        defer {
            sending = false
            refreshHealth()
        }
        var triedAfterLoss = false
        while true {
            refreshStatus()
            guard helperStatus == .enabled else {
                lastSetFailed = false
                return
            }
            let value = wanted
            sendAgain = false
            do {
                sleepDisabled = try await helper.setSleepDisabled(value)
                lastSetFailed = false
                health.answered(confirmed: sleepDisabled, wanted: value, now: now())
            } catch {
                // When an off request is lost the heartbeats have stopped too, so
                // the helper's watchdog clears the flag within its timeout.
                log.error("helper call failed: \(String(describing: error), privacy: .public)")
                if HelperCall.isConnectionLoss(error), !triedAfterLoss {
                    triedAfterLoss = true
                    continue
                }
                lastSetFailed = true
                health.failed(now: now())
                if health.takeRepair(), await registerAgain() { continue }
            }
            if wanted == value, !sendAgain { return }
        }
    }

    // The helper exited or was stopped. A helper that starts again clears
    // the flag of the one before it, so the wanted value is sent at once,
    // and not more often than the heartbeats would.
    func connectionLost() async {
        guard wanted, !sending, now() - lastSendAfterLoss >= heartbeatInterval else { return }
        lastSendAfterLoss = now()
        await send()
    }

    func removeSudoersEntry() async throws {
        try await sudoers.remove()
        refreshStatus()
    }

    // Also puts the flag back when the helper restarted and cleared it, and
    // tries again when the helper gave no answer before.
    func sendHeartbeat() async {
        guard wanted, !sending else { return }
        do {
            if try await helper.heartbeat() {
                guard wanted else { return }
                sleepDisabled = true
                health.answered(confirmed: true, wanted: true, now: now())
                return refreshHealth()
            }
        } catch {
            log.error("heartbeat failed: \(String(describing: error), privacy: .public)")
        }
        guard wanted else { return }
        await send()
    }

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        let interval = UInt64(heartbeatInterval * 1_000_000_000)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.sendHeartbeat()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }
}
