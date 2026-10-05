import Foundation
import os

@MainActor
final class BatteryOverride: ObservableObject {
    @Published private(set) var sudoersInstalled = false
    @Published private(set) var overrideActive: Bool
    @Published private(set) var lastError: String?

    private static let sudoersPath = "/etc/sudoers.d/caffeinagent"
    // `disablesleep 1` survives quit, crash and reboot, so remember that we set
    // it until a `disablesleep 0` is known to have run.
    private static let overrideFlagKey = "BatteryOverride.overrideSetByApp"
    private static let leakedOverrideMessage = "The sleep override may still be on, so this Mac may not sleep. To turn it off, run sudo pmset -a disablesleep 0 in Terminal."
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "BatteryOverride")
    private var refreshTimer: DispatchSourceTimer?

    private var overrideSetByApp: Bool {
        get { UserDefaults.standard.bool(forKey: Self.overrideFlagKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.overrideFlagKey) }
    }

    init() {
        overrideActive = UserDefaults.standard.bool(forKey: Self.overrideFlagKey)
        refreshSudoersStatus()
        if overrideActive {
            if sudoersInstalled {
                setEnabled(false)
            } else {
                clearFlagIfSleepAllowed()
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.refreshSudoersStatus()
            self?.clearFlagIfSleepAllowed()
        }
        timer.resume()
        self.refreshTimer = timer
    }

    func refreshSudoersStatus() {
        // `sudo -n -l <cmd>` returns 0 iff <cmd> is allowed without a password.
        // Doesn't execute the command, so there's no side effect.
        let (exitCode, _) = run("/usr/bin/sudo", args: [
            "-n", "-l", "/usr/bin/pmset", "-b", "disablesleep", "1"
        ])
        let installed = (exitCode == 0)
        if sudoersInstalled != installed { sudoersInstalled = installed }
    }

    func install() {
        let user = NSUserName()
        let line = "\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -b disablesleep 0, /usr/bin/pmset -b disablesleep 1"
        let escaped = line.replacingOccurrences(of: "\"", with: "\\\"")
        // Validate a temp copy so a bad rule never lands in /etc/sudoers.d.
        let script = """
        do shell script "tmp=$(/usr/bin/mktemp -t caffeinagent) && \
        echo '\(escaped)' > $tmp && \
        /usr/sbin/visudo -cf $tmp > /dev/null && \
        /usr/bin/install -m 0440 -o root -g wheel $tmp \(Self.sudoersPath); \
        rc=$?; rm -f $tmp; exit $rc" \
        with administrator privileges
        """
        let (exitCode, output) = run("/usr/bin/osascript", args: ["-e", script])
        if exitCode == 0 {
            lastError = nil
            refreshSudoersStatus()
        } else {
            lastError = output.isEmpty ? "The install was cancelled or failed." : output.trimmingCharacters(in: .whitespacesAndNewlines)
            log.error("install failed: \(output, privacy: .public)")
        }
    }

    func uninstall() {
        // Without the sudoers entry the app can no longer undo `disablesleep 1`,
        // so clear it as root before the entry goes away.
        let script = "do shell script \"/usr/bin/pmset -a disablesleep 0 && rm -f \(Self.sudoersPath)\" with administrator privileges"
        let (exitCode, output) = run("/usr/bin/osascript", args: ["-e", script])
        if exitCode == 0 {
            overrideSetByApp = false
            overrideActive = false
            lastError = nil
        } else {
            lastError = output.isEmpty ? "The uninstall was cancelled or failed." : output.trimmingCharacters(in: .whitespacesAndNewlines)
            log.error("uninstall failed: \(output, privacy: .public)")
        }
        refreshSudoersStatus()
    }

    func setEnabled(_ shouldEnable: Bool) {
        guard sudoersInstalled else {
            // The override may still be in force; only `disablesleep 0` may clear it.
            if overrideActive && lastError != Self.leakedOverrideMessage {
                lastError = Self.leakedOverrideMessage
            }
            return
        }
        guard shouldEnable != overrideActive else { return }
        let arg = shouldEnable ? "1" : "0"
        // Set before pmset so a crash right after it still leaves the flag.
        if shouldEnable { overrideSetByApp = true }
        let (exitCode, output) = run("/usr/bin/sudo", args: ["-n", "/usr/bin/pmset", "-b", "disablesleep", arg])
        if exitCode == 0 {
            overrideSetByApp = shouldEnable
            overrideActive = shouldEnable
            lastError = nil
            log.info("pmset disablesleep \(arg, privacy: .public)")
        } else {
            if shouldEnable { overrideSetByApp = false }
            lastError = shouldEnable ? "pmset failed: \(output)" : Self.leakedOverrideMessage
            log.error("pmset failed (exit \(exitCode)): \(output, privacy: .public)")
        }
    }

    // Lets the flag go once the user cleared the override by hand while the
    // sudoers entry is missing. Reading `pmset -g` needs no privileges.
    private func clearFlagIfSleepAllowed() {
        guard overrideActive, !sudoersInstalled else { return }
        let (exitCode, output) = run("/usr/bin/pmset", args: ["-g"])
        let sleepDisabled = output.split(separator: "\n").contains {
            $0.split(whereSeparator: \.isWhitespace) == ["SleepDisabled", "1"]
        }
        if exitCode == 0 && !sleepDisabled {
            overrideSetByApp = false
            overrideActive = false
            if lastError == Self.leakedOverrideMessage { lastError = nil }
        } else if lastError != Self.leakedOverrideMessage {
            lastError = Self.leakedOverrideMessage
        }
    }

    // Blocks without waitUntilExit, which spins the main run loop: the SIGTERM
    // handler or a timer could then run in the middle of a pmset call and see
    // stale state. The pipe is drained first so a full pipe cannot stall it.
    private func run(_ path: String, args: [String]) -> (Int32, String) {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        do {
            try task.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
