import Foundation
import os

// The XPC face of HelperCore. Every call and the watchdog timer run on one
// serial queue.
final class HelperService: NSObject, NSXPCListenerDelegate, SleepFlagHelperProtocol {
    private static let tickInterval: TimeInterval = 5
    private let queue = DispatchQueue(label: SleepFlagHelper.label)
    private let core = HelperCore(flag: SystemSleepFlag(), marker: MarkerFile(), timeout: SleepFlagHelper.heartbeatTimeout)
    private var timer: DispatchSourceTimer?
    private let log = Logger(subsystem: SleepFlagHelper.label, category: "HelperService")

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }()

    // Clears a flag that an earlier run left behind, before any client is served.
    func start() {
        queue.sync {
            if core.setByHelper { log.info("marker found at start, clearing SleepDisabled") }
            core.tick()
            updateTimer()
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SleepFlagHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setSleepDisabled(_ on: Bool, reply: @escaping (Bool) -> Void) {
        queue.async {
            let value = self.core.setSleepDisabled(on)
            self.log.info("set SleepDisabled \(on): now \(value)")
            self.updateTimer()
            reply(value)
        }
    }

    func status(reply: @escaping (Bool, Bool, String) -> Void) {
        queue.async {
            reply(self.core.sleepDisabled, self.core.setByHelper, Self.version)
        }
    }

    func heartbeat(reply: @escaping (Bool) -> Void) {
        queue.async {
            reply(self.core.heartbeat())
        }
    }

    // The timer runs only while the helper owns the flag, so an idle helper
    // never wakes up.
    private func updateTimer() {
        if core.setByHelper, timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.core.tick()
                if !self.core.setByHelper { self.log.info("SleepDisabled cleared by the watchdog") }
                self.updateTimer()
            }
            timer.resume()
            self.timer = timer
        } else if !core.setByHelper, let timer {
            timer.cancel()
            self.timer = nil
        }
    }
}
