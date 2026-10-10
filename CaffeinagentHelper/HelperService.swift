import Foundation
import os

// The XPC face of HelperCore and WakeAlarmCore. Every call and the two timers
// run on one serial queue.
final class HelperService: NSObject, NSXPCListenerDelegate, SleepFlagHelperProtocol {
    private static let tickInterval: TimeInterval = 5
    // The lease of the wake alarm is 10 minutes, so half a minute is close
    // enough, and the system may move the tick to save power.
    private static let alarmTickInterval: TimeInterval = 30
    private let queue = DispatchQueue(label: SleepFlagHelper.label)
    private let core: HelperCore
    private let alarm: WakeAlarmCore
    private let exitProcess: (Int32) -> Void
    private var timer: DispatchSourceTimer?
    private var alarmTimer: DispatchSourceTimer?
    private var termination: DispatchSourceSignal?
    /// The helper leaves after `retire`. Read and written on the queue.
    private var retiring = false
    /// The connections of the app that are open. Read and written on the queue.
    private var clients: Set<UUID> = []
    /// The exit after `retire` waits for the reply to go out, at most this long.
    private static let retireGrace: TimeInterval = 1
    private let log = Logger(subsystem: SleepFlagHelper.label, category: "HelperService")

    // The cores and the exit are passed in, so a test can stop the service
    // without the kernel flag, without a power event and without leaving
    // the process.
    init(core: HelperCore, alarm: WakeAlarmCore, exitProcess: @escaping (Int32) -> Void = { exit($0) }) {
        self.core = core
        self.alarm = alarm
        self.exitProcess = exitProcess
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }()

    // Clears a flag and takes away a wake alarm that an earlier run left
    // behind, before any client is served.
    func start() {
        queue.sync {
            if core.setByHelper { log.info("marker found at start, clearing SleepDisabled") }
            core.tick()
            updateTimer()
            alarm.start()
            updateAlarmTimer()
        }
    }

    // launchd sends SIGTERM and waits for the exit before it kills. The
    // handler runs on the queue, after a call that is under way.
    func exitOnTermination(signal number: Int32 = SIGTERM) {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
        source.setEventHandler { [weak self, exitProcess] in
            guard let self else { return exitProcess(0) }
            if self.core.setByHelper { self.log.info("stopping, clearing SleepDisabled") }
            self.core.shutdown()
            self.alarm.shutdown()
            self.exitProcess(0)
        }
        source.resume()
        termination = source
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The next connection is for the helper that launchd starts after this one.
        let id = UUID()
        let accepted = queue.sync { () -> Bool in
            if retiring { return false }
            clients.insert(id)
            alarm.clientConnected()
            return true
        }
        guard accepted else { return false }
        connection.exportedInterface = NSXPCInterface(with: SleepFlagHelperProtocol.self)
        connection.exportedObject = self
        // The app quit or died. The handlers hold an id and not the
        // connection, so the connection can go.
        connection.invalidationHandler = { [weak self] in self?.clientGone(id) }
        connection.interruptionHandler = { [weak self] in self?.clientGone(id) }
        connection.resume()
        return true
    }

    // The wake alarm has no one behind it when the last connection of the
    // app ended: the app sends no cancel when it dies. WakeAlarmCore takes
    // the alarm away after its grace, unless a new connection came, as
    // when the app starts again after an update. Both handlers of a
    // connection can run, and it counts once.
    private func clientGone(_ id: UUID) {
        queue.async {
            guard self.clients.remove(id) != nil else { return }
            self.alarm.clientGone()
            guard self.clients.isEmpty, self.alarm.needsTicks else { return }
            // Dispatch counts this in awake time, like the grace.
            self.queue.asyncAfter(deadline: .now() + self.alarm.graceAfterClients) {
                self.alarm.tick()
                if !self.alarm.needsTicks { self.log.info("wake alarm cancelled: the app has no connection") }
                self.updateAlarmTimer()
            }
        }
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

    // The app was updated, and this process is still the helper of the
    // version before it. It leaves as when launchd stops it, with exit code
    // 0: KeepAlive in the plist starts the helper again only after a crash,
    // so launchd starts the new binary on the next connection.
    func retire(reply: @escaping () -> Void) {
        let connection = NSXPCConnection.current()
        queue.async {
            if self.core.setByHelper { self.log.info("retiring, clearing SleepDisabled") }
            self.retiring = true
            self.core.shutdown()
            self.alarm.shutdown()
            reply()
            guard let connection else { return self.exitProcess(0) }
            // After the reply went out.
            connection.scheduleSendBarrierBlock { self.exitProcess(0) }
            self.queue.asyncAfter(deadline: .now() + Self.retireGrace) { self.exitProcess(0) }
        }
    }

    // The one number is all that comes from the client. The owner and the
    // type of the event are constants of WakeAlarmCore and SystemWakeEvents.
    func setWakeAlarm(at time: Double, reply: @escaping (Double, Int) -> Void) {
        queue.async {
            // After `retire` took the alarm away, a call that was under
            // way sets none: it would stay behind a helper that left.
            if self.retiring {
                reply(0, WakeAlarmRefusal.notCancelled.rawValue)
                return
            }
            let result = self.alarm.set(at: time)
            switch result {
            case .set(let time): self.log.info("wake alarm set at \(time, privacy: .public)")
            case .cancelled: self.log.info("wake alarm cancelled")
            case .refused(let reason): self.log.info("wake alarm refused: \(reason.rawValue, privacy: .public)")
            case .helperNotAvailable: break
            }
            self.updateAlarmTimer()
            let answer = result.reply
            reply(answer.time, answer.code)
        }
    }

    // Runs only while a wake alarm has a lease, so an idle helper never
    // wakes up. Dispatch counts the interval in awake time, like the lease.
    private func updateAlarmTimer() {
        if alarm.needsTicks, alarmTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.alarmTickInterval, repeating: Self.alarmTickInterval, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.alarm.tick()
                if !self.alarm.needsTicks { self.log.info("wake alarm cancelled: the app did not ask again") }
                self.updateAlarmTimer()
            }
            timer.resume()
            alarmTimer = timer
        } else if !alarm.needsTicks, let alarmTimer {
            alarmTimer.cancel()
            self.alarmTimer = nil
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
