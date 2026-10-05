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

    func setSleepDisabled(_ on: Bool) async throws -> Bool {
        try await call { proxy, done in
            proxy.setSleepDisabled(on) { done(.success($0)) }
        }
    }

    func status() async throws -> (sleepDisabled: Bool, setByHelper: Bool, version: String) {
        try await call { proxy, done in
            proxy.status { sleepDisabled, setByHelper, version in
                done(.success((sleepDisabled, setByHelper, version)))
            }
        }
    }

    func heartbeat() async throws -> Bool {
        try await call { proxy, done in
            proxy.heartbeat { done(.success($0)) }
        }
    }

    // NSXPC calls either the reply block or the error handler, once.
    private func call<T>(_ body: @escaping (SleepFlagHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let connection = currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? SleepFlagHelperProtocol else {
                continuation.resume(throwing: CocoaError(.xpcConnectionInvalid))
                return
            }
            body(helper) { continuation.resume(with: $0) }
        }
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
            guard let self else { return }
            self.lock.lock()
            if self.connection === connection { self.connection = nil }
            self.lock.unlock()
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

struct SudoersEntry: SudoersCleaning {
    // Same path as BatteryOverride, which wrote it.
    private static let path = "/etc/sudoers.d/caffeinagent"

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
