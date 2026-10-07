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
    // Drops the connection, so the next call makes a new one.
    func reconnect()
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
    /// What Preferences and the menu say about the helper.
    @PublishedOnChange private(set) var setup = HelperSetup.notSetUp
    /// The last try to set the flag ended without an answer.
    private(set) var lastSetFailed = false
    /// "On" went out and no answer came back. The helper may hold the flag
    /// all the same: the app's signing check is on the answer only.
    private(set) var flagUnconfirmed = false

    private let service: HelperServiceManaging
    private let helper: SleepFlagHelperConnecting
    private let sudoers: SudoersCleaning
    private let heartbeatInterval: TimeInterval
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let sleep: (TimeInterval) async -> Void
    private var health = HelperHealth()
    private var wanted = false
    private var sending = false
    private var sendAgain = false
    private var repairing = false
    /// A repair took the helper away and did not bring it back.
    private var lostByRepair = false
    private var slowRetriesLeft = HelperRepair.slowRetries
    private var lastRepairEnd = -TimeInterval.infinity
    private var lastSendAfterLoss = -TimeInterval.infinity
    private var lastOffWithTheHelperOff = -TimeInterval.infinity
    private var lastSampleAt: TimeInterval
    private var heartbeatsHeldBack = false
    private var heartbeatTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "SleepFlagController")

    static let wasSetUpKey = "SleepFlagController.helperWasSetUp"
    /// The samples are 2 or 5 seconds apart. After this long without one
    /// the sampling hangs, and nobody watches the battery and the heat.
    static let samplePatience: TimeInterval = 30

    init(
        service: HelperServiceManaging,
        helper: SleepFlagHelperConnecting,
        sudoers: SudoersCleaning,
        heartbeatInterval: TimeInterval = SleepFlagHelper.heartbeatInterval,
        defaults: UserDefaults = .standard,
        // The clock of the helper's watchdog: it stands still while the Mac sleeps.
        now: @escaping () -> TimeInterval = SampleGap.awakeSeconds,
        sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.service = service
        self.helper = helper
        self.sudoers = sudoers
        self.heartbeatInterval = heartbeatInterval
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.lastSampleAt = now()
        self.helperStatus = service.status
        refreshStatus()
        helper.onConnectionLost { [weak self] in
            Task { @MainActor in await self?.connectionLost() }
        }
    }

    /// The helper was enabled on this Mac at some time, and the user did
    /// not remove it.
    var wasSetUp: Bool { defaults.bool(forKey: Self.wasSetUpKey) }

    // The user can allow or remove the helper in System Settings at any time.
    func refreshStatus() {
        let status = service.status
        if helperStatus != status { helperStatus = status }
        switch status {
        case .enabled:
            lostByRepair = false
            if !wasSetUp { defaults.set(true, forKey: Self.wasSetUpKey) }
        case .requiresApproval:
            lostByRepair = false
        case .notRegistered, .notFound:
            break
        }
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
        let next = currentSetup
        if setup != next { setup = next }
    }

    private var currentSetup: HelperSetup {
        if repairing { return .repairing }
        switch helperStatus {
        case .enabled:
            return notResponding ? .notResponding : .ready
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            // While agent caffeine still tries, the user has nothing to set up.
            if lostByRepair, slowRetriesLeft > 0 { return .notResponding }
            return lostByRepair || wasSetUp ? .lost : .notSetUp
        }
    }

    func install() async throws {
        do {
            try service.register()
        } catch {
            refreshStatus()
            if helperStatus == .requiresApproval { throw SleepFlagError.requiresApproval }
            log.error("register failed: \(HelperRepair.describe(error), privacy: .public)")
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
            logSend(false, .remove)
            sleepDisabled = try await helper.setSleepDisabled(false)
            if try await helper.status().setByHelper { throw SleepFlagError.flagNotCleared }
            flagUnconfirmed = false
        }
        try await service.unregister()
        defaults.removeObject(forKey: Self.wasSetUpKey)
        lostByRepair = false
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
    /// start the new one. A helper that gives no version gets a new
    /// connection first, and is registered again when that does not help,
    /// once in a launch.
    func replaceHelper(ifNot appVersion: String) async {
        refreshStatus()
        guard helperStatus == .enabled, !repairing else { return }
        var running: String?
        do {
            running = try await helperVersion()
        } catch {
            log.error("the helper gave no version: \(String(describing: error), privacy: .public)")
            health.failed(now: now())
            guard health.takeRepair(atOnce: true) else { return refreshHealth() }
        }
        guard running != appVersion, !repairing else { return }
        _ = await duringRepair {
            var running = running
            if running == nil { running = await self.versionOnANewConnection() }
            if running == appVersion { return true }
            if let running {
                self.log.info("helper is \(running, privacy: .public), app is \(appVersion, privacy: .public): registering again")
                // So the helper that is stopped has no flag to clear on its way out.
                self.logSend(false, .replace)
                _ = try? await self.helper.setSleepDisabled(false)
            }
            return await self.registerAgain()
        }
        await send(.repair)
    }

    /// "Try again" in the menu and in Preferences. A helper that answers is
    /// left alone, one that does not is registered again. When that needs
    /// the user's approval, the helper's state says so.
    func repairHelper() async {
        refreshStatus()
        guard !repairing else { return }
        switch helperStatus {
        case .enabled:
            health.repairAsked()
            _ = await repair()
        case .notRegistered, .notFound:
            guard lostByRepair else { return }
            _ = await duringRepair { await self.registerAndWait() }
        case .requiresApproval:
            return
        }
        await send(.repair)
    }

    /// A repair took the helper away and could not register it again.
    /// Later the system lets it pass, so it is tried again now and then.
    var repairIsDue: Bool {
        lostByRepair && !repairing && slowRetriesLeft > 0 && now() - lastRepairEnd >= HelperRepair.slowRetryInterval
    }

    func retryRepairIfDue() async {
        guard repairIsDue else { return }
        refreshStatus()
        guard repairIsDue else { return }
        slowRetriesLeft -= 1
        log.info("registering the helper again, \(self.slowRetriesLeft) more tries after this one")
        _ = await duringRepair { await self.registerAndWait() }
        await send(.repair)
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

    // MARK: Repair

    /// First a new connection. Only when the signing check fails again, or
    /// two tries got no answer, the helper is registered again. True when
    /// the helper answers afterwards.
    private func repair() async -> Bool {
        guard !repairing else { return false }
        return await duringRepair {
            if await self.versionOnANewConnection() != nil { return true }
            return await self.registerAgain()
        }
    }

    private func duringRepair(_ work: () async -> Bool) async -> Bool {
        repairing = true
        refreshHealth()
        let answers = await work()
        repairing = false
        lastRepairEnd = now()
        refreshHealth()
        return answers
    }

    private func versionOnANewConnection() async -> String? {
        for _ in 1...HelperRepair.reconnectTries {
            helper.reconnect()
            do {
                return try await helper.status().version
            } catch {
                log.error("no answer on a new connection: \(String(describing: error), privacy: .public)")
                if HelperCall.isSigningFailure(error) { return nil }
            }
        }
        return nil
    }

    // unregister() stops the helper, and a helper that is stopped clears a
    // flag it owns. True when the new helper answers.
    private func registerAgain() async -> Bool {
        log.info("registering the helper again")
        do {
            try await service.unregister()
            let gone = await waitForStatus(patience: HelperRepair.removalPatience) { $0 == .notRegistered || $0 == .notFound }
            if !gone { log.error("the helper is still registered after it was removed") }
        } catch {
            log.error("removing the helper failed: \(HelperRepair.describe(error), privacy: .public)")
        }
        // The flag went with the old helper, whatever a call under way says.
        sendAgain = sending
        return await registerAndWait()
    }

    /// Registers the helper, waits until it is enabled and until it gives
    /// its first answer. True when it answers.
    private func registerAndWait() async -> Bool {
        var backoff = HelperRepair.registerBackoff[...]
        var registered = false
        while !registered {
            do {
                try service.register()
                registered = true
            } catch {
                log.error("registering the helper failed: \(HelperRepair.describe(error), privacy: .public)")
                let status = service.status
                if status == .enabled { break }
                guard status != .requiresApproval, HelperRepair.isNotPermitted(error), let delay = backoff.popFirst() else {
                    return finishRegistering(answers: false)
                }
                await sleep(delay)
            }
        }
        _ = await waitForStatus(patience: HelperRepair.enablePatience) { $0 == .enabled || $0 == .requiresApproval }
        guard service.status == .enabled else { return finishRegistering(answers: false) }
        helper.reconnect()
        for attempt in 1...HelperRepair.firstAnswerTries {
            do {
                _ = try await helper.status()
                return finishRegistering(answers: true)
            } catch {
                log.error("the new helper gave no answer: \(String(describing: error), privacy: .public)")
                if attempt < HelperRepair.firstAnswerTries { await sleep(HelperRepair.firstAnswerInterval) }
            }
        }
        return finishRegistering(answers: false)
    }

    private func finishRegistering(answers: Bool) -> Bool {
        refreshStatus()
        switch helperStatus {
        case .enabled:
            if !answers { health.repairDidFail() }
        case .requiresApproval:
            break
        case .notRegistered, .notFound:
            lostByRepair = true
            health.repairDidFail()
        }
        let state = helperStatus == .enabled ? (answers ? "enabled and answers" : "enabled and gives no answer") : "not enabled"
        log.info("the helper is \(state, privacy: .public) after registering again")
        return answers
    }

    private func waitForStatus(patience: TimeInterval, _ reached: (HelperStatus) -> Bool) async -> Bool {
        var polls = Int(patience / HelperRepair.pollInterval)
        while !reached(service.status) {
            guard polls > 0 else { return false }
            polls -= 1
            await sleep(HelperRepair.pollInterval)
        }
        return true
    }

    // MARK: Flag

    /// For quitting, where nothing can await: blocks the caller for at most
    /// `timeout` seconds. When the call is late or lost, the heartbeats
    /// have stopped and the helper's watchdog clears the flag.
    func clearForQuit(timeout: TimeInterval) {
        let owed = wanted || sleepDisabled || flagUnconfirmed
        wanted = false
        stopHeartbeat()
        guard owed, helperStatus == .enabled else { return }
        logSend(false, .quit)
        let done = DispatchSemaphore(value: 0)
        let helper = helper
        Task.detached {
            _ = try? await helper.setSleepDisabled(false)
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    func setSleepDisabled(_ on: Bool) async -> Bool {
        let reason: FlagReason = lastSetFailed && on == wanted ? .retry : .decision
        wanted = on
        if on { startHeartbeat() } else { stopHeartbeat() }
        await send(reason)
        return sleepDisabled
    }

    /// The decision no longer wants the flag, whatever the state of the
    /// helper is. A helper that System Settings no longer calls enabled
    /// can still run and answer, and `setSleepDisabled(false)` never
    /// reaches it: without this the heartbeats would keep its flag on.
    /// - Returns: the try to send "off" to such a helper, nil for none.
    @discardableResult
    func stopWanting() -> Task<Void, Never>? {
        wanted = false
        stopHeartbeat()
        guard offIsOwedWithTheHelperOff else { return nil }
        return Task { await self.sendOffWithTheHelperOff() }
    }

    /// With the helper enabled the caller's request sends "off".
    private var offIsOwedWithTheHelperOff: Bool {
        !wanted && helperStatus != .enabled && (sleepDisabled || flagUnconfirmed) && !sending && !repairing
            && now() - lastOffWithTheHelperOff >= heartbeatInterval
    }

    /// A helper that is gone gives no answer, and the next try comes no
    /// sooner than a heartbeat would.
    private func sendOffWithTheHelperOff() async {
        guard offIsOwedWithTheHelperOff else { return }
        lastOffWithTheHelperOff = now()
        logSend(false, .decision)
        do {
            sleepDisabled = try await helper.setSleepDisabled(false)
            flagUnconfirmed = false
        } catch {
            log.error("no answer from a helper that is not enabled: \(String(describing: error), privacy: .public)")
        }
        refreshHealth()
    }

    /// Every value the app sends is in the log with its reason.
    private func logSend(_ value: Bool, _ reason: FlagReason) {
        log.info("sending SleepDisabled \(value) to the helper: \(reason.rawValue, privacy: .public)")
    }

    /// Brings the helper to the wanted value. One call at a time: a value
    /// that changes while a call is under way is sent after it.
    private func send(_ reason: FlagReason) async {
        guard !sending, !repairing else { return }
        sending = true
        defer {
            sending = false
            refreshHealth()
        }
        var reason = reason
        var triedAfterLoss = false
        while true {
            refreshStatus()
            guard helperStatus == .enabled else {
                lastSetFailed = false
                return
            }
            // The one who repairs sends the value when the helper is back.
            guard !repairing else { return }
            let value = wanted
            sendAgain = false
            logSend(value, reason)
            do {
                sleepDisabled = try await helper.setSleepDisabled(value)
                lastSetFailed = false
                flagUnconfirmed = false
                health.answered(confirmed: sleepDisabled, wanted: value, now: now())
            } catch {
                // When an off request is lost the heartbeats have stopped too, so
                // the helper's watchdog clears the flag within its timeout.
                log.error("helper call failed: \(String(describing: error), privacy: .public)")
                if value { flagUnconfirmed = true }
                if HelperCall.isConnectionLoss(error), !triedAfterLoss {
                    triedAfterLoss = true
                    reason = .retry
                    continue
                }
                lastSetFailed = true
                health.failed(now: now())
                // A helper whose signature does not pass is not waited for.
                if health.takeRepair(atOnce: HelperCall.isSigningFailure(error)), await repair() {
                    reason = .repair
                    continue
                }
            }
            if wanted == value, !sendAgain { return }
            reason = wanted == value ? .repair : .decision
        }
    }

    // The helper exited or was stopped. A helper that starts again clears
    // the flag of the one before it, so the wanted value is sent at once,
    // and not more often than the heartbeats would.
    func connectionLost() async {
        guard wanted, !sending, !repairing, now() - lastSendAfterLoss >= heartbeatInterval else { return }
        lastSendAfterLoss = now()
        await send(.connectionLost)
    }

    func removeSudoersEntry() async throws {
        try await sudoers.remove()
        refreshStatus()
    }

    // Also puts the flag back when the helper restarted and cleared it, and
    // tries again when the helper gave no answer before.
    func sendHeartbeat() async {
        guard wanted, !sending, !repairing else { return }
        do {
            if try await helper.heartbeat() {
                guard wanted else { return }
                sleepDisabled = true
                flagUnconfirmed = false
                health.answered(confirmed: true, wanted: true, now: now())
                return refreshHealth()
            }
        } catch {
            log.error("heartbeat failed: \(String(describing: error), privacy: .public)")
        }
        guard wanted else { return }
        await send(.heartbeat)
    }

    /// A sample of the engine ended and its battery and heat check ran.
    func sampleCompleted() {
        lastSampleAt = now()
    }

    /// The heartbeat of the timer. The flag blocks the kernel's own sleep
    /// for low battery and heat, and only a sample checks them. So while
    /// the sampling hangs no heartbeat goes out, and the helper's watchdog
    /// clears the flag. The first sample after that sends it again.
    func sendHeartbeatWhileSampling() async {
        let stale = now() - lastSampleAt > Self.samplePatience
        if stale != heartbeatsHeldBack {
            heartbeatsHeldBack = stale
            if stale, wanted { log.error("no sample for \(Int(Self.samplePatience)) seconds: the heartbeats stop until the next one") }
        }
        guard !stale else { return }
        await sendHeartbeat()
    }

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        let interval = UInt64(heartbeatInterval * 1_000_000_000)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.sendHeartbeatWhileSampling()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }
}
