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
// cannot be reached.
protocol SleepFlagHelperConnecting {
    func setSleepDisabled(_ on: Bool) async throws -> Bool
    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String)
    func heartbeat() async throws -> Bool
}

// The sudoers entry of the method this helper replaced.
protocol SudoersCleaning {
    var entryExists: Bool { get }
    func remove() async throws
}

/// Which value to send to the helper, so it is called only on a change.
struct SleepFlagRequest: Equatable {
    private(set) var sent: Bool?

    /// The value to send now, nil for no call. A helper that is not enabled
    /// gets no call. The next time it is enabled it gets the wanted value,
    /// also when that is off: the call then clears a flag that an earlier
    /// run left on.
    mutating func next(wanted: Bool, helperEnabled: Bool) -> Bool? {
        guard helperEnabled else {
            sent = nil
            return nil
        }
        guard sent != wanted else { return nil }
        sent = wanted
        return wanted
    }
}

@MainActor
final class SleepFlagController: ObservableObject, SleepFlagControlling {
    @Published private(set) var helperStatus: HelperStatus
    // The last value the helper confirmed.
    @Published private(set) var sleepDisabled = false
    @Published private(set) var needsSudoersCleanup = false

    private let service: HelperServiceManaging
    private let helper: SleepFlagHelperConnecting
    private let sudoers: SudoersCleaning
    private let heartbeatInterval: TimeInterval
    private var wanted = false
    private var heartbeatTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "SleepFlagController")

    init(
        service: HelperServiceManaging,
        helper: SleepFlagHelperConnecting,
        sudoers: SudoersCleaning,
        heartbeatInterval: TimeInterval = SleepFlagHelper.heartbeatInterval
    ) {
        self.service = service
        self.helper = helper
        self.sudoers = sudoers
        self.heartbeatInterval = heartbeatInterval
        self.helperStatus = service.status
        refreshStatus()
    }

    // The user can allow or remove the helper in System Settings at any time.
    func refreshStatus() {
        let status = service.status
        if helperStatus != status { helperStatus = status }
        let cleanup = sudoers.entryExists
        if needsSudoersCleanup != cleanup { needsSudoersCleanup = cleanup }
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
    /// start the new one. Not tested with a real update yet: check that the
    /// approval in Login Items survives it.
    func replaceHelper(ifNot appVersion: String) async {
        refreshStatus()
        guard helperStatus == .enabled, let running = try? await helper.status(), running.version != appVersion else { return }
        log.info("helper is \(running.version, privacy: .public), app is \(appVersion, privacy: .public): registering again")
        do {
            try await uninstall()
            try service.register()
        } catch {
            log.error("replacing the helper failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStatus()
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
        refreshStatus()
        guard helperStatus == .enabled else { return sleepDisabled }
        do {
            sleepDisabled = try await helper.setSleepDisabled(on)
        } catch {
            // When an off request is lost the heartbeats have stopped too, so
            // the helper's watchdog clears the flag within its timeout.
            log.error("helper call failed: \(error.localizedDescription, privacy: .public)")
        }
        return sleepDisabled
    }

    func removeSudoersEntry() async throws {
        try await sudoers.remove()
        refreshStatus()
    }

    // Also puts the flag back when the helper restarted and cleared it.
    func sendHeartbeat() async {
        guard wanted else { return }
        do {
            let value = try await helper.heartbeat()
            guard wanted else { return }
            sleepDisabled = value ? true : try await helper.setSleepDisabled(true)
        } catch {
            log.error("heartbeat failed: \(error.localizedDescription, privacy: .public)")
        }
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
