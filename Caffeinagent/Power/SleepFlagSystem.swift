import Foundation
import ServiceManagement

extension SleepFlagController {
    convenience init() {
        self.init(service: DaemonService(), helper: XPCSleepFlagHelper(), sudoers: SudoersEntry())
    }
}

struct DaemonService: HelperServiceManaging {
    private var daemon: SMAppService { SMAppService.daemon(plistName: SleepFlagHelper.plistName) }

    var status: HelperStatus {
        switch daemon.status {
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .enabled: return .enabled
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws {
        try daemon.register()
    }

    func unregister() async throws {
        try await daemon.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

final class XPCSleepFlagHelper: SleepFlagHelperConnecting {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    /// The calls that wait for an answer, each with its connection.
    private var pending: [UUID: (connection: ObjectIdentifier, fail: (Error) -> Void)] = [:]
    private var lostHandler: (() -> Void)?

    func onConnectionLost(_ handler: @escaping () -> Void) {
        lock.lock()
        lostHandler = handler
        lock.unlock()
    }

    func setSleepDisabled(_ on: Bool) async throws -> Bool {
        try await call { proxy, done in
            proxy.setSleepDisabled(on) { done($0) }
        }
    }

    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) {
        try await call { proxy, done in
            proxy.status { sleepDisabled, setByHelper, version in
                done((sleepDisabled, setByHelper, version))
            }
        }
    }

    func heartbeat() async throws -> Bool {
        try await call { proxy, done in
            proxy.heartbeat { done($0) }
        }
    }

    // The reply, the error handler, the end of the connection or the
    // timeout answers the call, whichever is first. A connection that
    // gave no answer in time is dropped, and the next call makes a new one.
    private func call<T>(_ body: @escaping (SleepFlagHelperProtocol, @escaping (T) -> Void) -> Void) async throws -> T {
        let connection = currentConnection()
        let id = UUID()
        defer { forget(id) }
        return try await HelperCall.run(onTimeout: { connection.invalidate() }) { (answer: OneAnswer<T>) in
            remember(id, on: connection) { answer.give(.failure($0)) }
            let proxy = connection.remoteObjectProxyWithErrorHandler { answer.give(.failure($0)) }
            guard let helper = proxy as? SleepFlagHelperProtocol else {
                answer.give(.failure(CocoaError(.xpcConnectionInvalid)))
                return
            }
            body(helper) { answer.give(.success($0)) }
        }
    }

    private func remember(_ id: UUID, on connection: NSXPCConnection, fail: @escaping (Error) -> Void) {
        lock.lock()
        pending[id] = (ObjectIdentifier(connection), fail)
        lock.unlock()
    }

    private func forget(_ id: UUID) {
        lock.lock()
        pending[id] = nil
        lock.unlock()
    }

    // The helper exited or was stopped (interrupted), or the connection is
    // of no more use (invalid). Either way no reply comes for its calls.
    private func lost(_ connection: NSXPCConnection, invalid: Bool) {
        lock.lock()
        if invalid, self.connection === connection { self.connection = nil }
        let failed = pending.filter { $0.value.connection == ObjectIdentifier(connection) }
        failed.keys.forEach { pending[$0] = nil }
        let handler = lostHandler
        lock.unlock()
        failed.values.forEach { $0.fail(HelperCallError.connectionLost) }
        handler?()
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: SleepFlagHelper.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepFlagHelperProtocol.self)
        // The app talks only to the helper this team signed.
        connection.setCodeSigningRequirement(SleepFlagHelper.requirement(identifier: SleepFlagHelper.label))
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.lost(connection, invalid: true)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.lost(connection, invalid: false)
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

struct SudoersEntry: SudoersCleaning {
    // Written by the builds that ran `sudo pmset` themselves.
    fileprivate static let path = "/etc/sudoers.d/caffeinagent"

    var entryExists: Bool { FileManager.default.fileExists(atPath: Self.path) }

    func remove() async throws {
        let script = "do shell script \"rm -f \(Self.path)\" with administrator privileges"
        let (exitCode, output): (Int32, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                task.arguments = ["-e", script]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do {
                    try task.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                continuation.resume(returning: (task.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
        guard exitCode == 0 else {
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SudoersCleanupError(message: message.isEmpty ? "The removal was cancelled or failed." : message)
        }
    }
}

struct SudoersCleanupError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// The builds before the helper set SleepDisabled through `sudo pmset` and
// remembered it in UserDefaults, because the flag survives a quit.
enum LegacyBatteryOverride {
    private static let flagKey = "BatteryOverride.overrideSetByApp"

    /// Clears a flag such a build left on, then forgets it. `sudo -n` never
    /// asks for a password: without the sudoers entry it fails at once.
    static func clearLeftover(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: flagKey) else { return }
        defaults.removeObject(forKey: flagKey)
        guard FileManager.default.fileExists(atPath: SudoersEntry.path) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // Word for word the command the sudoers entry allows.
        task.arguments = ["-n", "/usr/bin/pmset", "-b", "disablesleep", "0"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        guard (try? task.run()) != nil else { return }
        exited.wait()
    }
}
