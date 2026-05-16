import Foundation
import os

@MainActor
final class BatteryOverride: ObservableObject {
    @Published private(set) var sudoersInstalled = false
    @Published private(set) var overrideActive = false
    @Published private(set) var lastError: String?

    private static let sudoersPath = "/etc/sudoers.d/caffeinagent"
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "BatteryOverride")
    private var refreshTimer: DispatchSourceTimer?

    init() {
        refreshSudoersStatus()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 30)
        timer.setEventHandler { [weak self] in self?.refreshSudoersStatus() }
        timer.resume()
        self.refreshTimer = timer
    }

    func refreshSudoersStatus() {
        // `sudo -n -l <cmd>` returns 0 iff <cmd> is allowed without a password.
        // Doesn't execute the command, so there's no side effect.
        let (exitCode, _) = run("/usr/bin/sudo", args: [
            "-n", "-l", "/usr/bin/pmset", "-b", "disablesleep", "1"
        ])
        sudoersInstalled = (exitCode == 0)
    }

    func install() {
        let user = NSUserName()
        let line = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -b disablesleep 0, /usr/bin/pmset -b disablesleep 1"
        let escaped = line.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "echo '\(escaped)' > \(Self.sudoersPath) && \
        /bin/chmod 0440 \(Self.sudoersPath) && \
        /usr/sbin/visudo -cf \(Self.sudoersPath) > /dev/null || (rm -f \(Self.sudoersPath); exit 1)" \
        with administrator privileges
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let err = Pipe()
        task.standardError = err
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                lastError = nil
                refreshSudoersStatus()
            } else {
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                lastError = stderr.isEmpty ? "install cancelled or failed" : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                log.error("install failed: \(stderr, privacy: .public)")
            }
        } catch {
            lastError = error.localizedDescription
            log.error("osascript spawn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func uninstall() {
        let script = "do shell script \"rm -f \(Self.sudoersPath)\" with administrator privileges"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            log.error("uninstall failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshSudoersStatus()
    }

    func setEnabled(_ shouldEnable: Bool) {
        guard sudoersInstalled else {
            if overrideActive { overrideActive = false }
            return
        }
        guard shouldEnable != overrideActive else { return }
        let arg = shouldEnable ? "1" : "0"
        let (exitCode, output) = run("/usr/bin/sudo", args: ["-n", "/usr/bin/pmset", "-b", "disablesleep", arg])
        if exitCode == 0 {
            overrideActive = shouldEnable
            lastError = nil
            log.info("pmset disablesleep \(arg, privacy: .public)")
        } else {
            lastError = "pmset failed: \(output)"
            log.error("pmset failed (exit \(exitCode)): \(output, privacy: .public)")
        }
    }

    private func run(_ path: String, args: [String]) -> (Int32, String) {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
