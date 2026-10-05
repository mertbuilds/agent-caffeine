import Foundation

protocol SleepFlagAccessing {
    // nil when the kernel value cannot be read.
    func read() -> Bool?
    // Writes, reads back and retries. Returns the value the kernel reports,
    // or the opposite of `on` when it cannot be confirmed. Without `force`
    // nothing is written when the kernel already reports `on`.
    func set(_ on: Bool, force: Bool) -> Bool
}

extension SleepFlagAccessing {
    func set(_ on: Bool) -> Bool { set(on, force: false) }
}

protocol MarkerStoring {
    var exists: Bool { get }
    func write() -> Bool
    func remove()
}

// Everything the helper decides, with the kernel flag, the marker file and
// the clock passed in. Not thread safe: HelperService calls it on one queue.
final class HelperCore {
    private let flag: SleepFlagAccessing
    private let marker: MarkerStoring
    private let now: () -> TimeInterval
    private var watchdog: SleepFlagWatchdog
    // How many more ticks have to find the flag off before the marker of an
    // earlier run is dropped. Zero when there was no such marker.
    private var recoveryChecksLeft: Int
    private var recoveryWritten = false

    // At boot the kernel can report the flag off while powerd has not yet
    // applied the stored setting, which is still on. So one read is no proof.
    static let recoveryChecks = 3

    var setByHelper: Bool { watchdog.setByHelper }
    var sleepDisabled: Bool { flag.read() ?? false }

    init(flag: SleepFlagAccessing, marker: MarkerStoring, timeout: TimeInterval = 60, now: @escaping () -> TimeInterval = HelperCore.awakeSeconds) {
        self.flag = flag
        self.marker = marker
        self.now = now
        self.watchdog = SleepFlagWatchdog(markerExists: marker.exists, timeout: timeout)
        self.recoveryChecksLeft = watchdog.setByHelper ? Self.recoveryChecks : 0
    }

    // Seconds the Mac was awake since boot. CLOCK_UPTIME_RAW stands still
    // while the Mac sleeps, and that is wanted: no heartbeat arrives during
    // sleep, so a clock that counts sleep (CLOCK_MONOTONIC and
    // CLOCK_MONOTONIC_RAW both do) would clear the flag right after wake,
    // before the app had its turn. The date is no use at all: a time sync or
    // a manual change moves it.
    static func awakeSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }

    func setSleepDisabled(_ on: Bool) -> Bool {
        guard on else {
            if recoveryChecksLeft > 0 { return recover() }
            // A flag someone else set is theirs to clear.
            return watchdog.setByHelper ? clear() : sleepDisabled
        }
        recoveryChecksLeft = 0
        if !watchdog.setByHelper {
            // Already on without us: leave it alone and take no ownership.
            if flag.read() == true { return true }
            // The marker goes first, so a crash right after the set still
            // leaves it. Without a marker the flag could never be cleaned up.
            guard marker.write() else { return false }
        }
        watchdog.willSet(now: now())
        if flag.set(true) { return true }
        // Not confirmed is not the same as not written: powerd may still
        // apply the stored "on". So false is written whatever the kernel
        // reports, and the marker stays until the flag was off on every
        // check, as after a start with a marker.
        recoveryChecksLeft = Self.recoveryChecks
        recoveryWritten = false
        return recover()
    }

    func heartbeat() -> Bool {
        watchdog.heartbeat(now: now())
        return sleepDisabled
    }

    func tick() {
        if recoveryChecksLeft > 0 {
            _ = recover()
        } else if watchdog.tick(now: now()) == .clearFlag {
            _ = clear()
        }
    }

    // launchd stops the helper: the user switched it off in Login Items, the
    // app is being removed, or the Mac shuts down. Nobody is left to clear a
    // flag the helper owns, so it goes now. A clear that cannot be confirmed
    // keeps the marker, and the next start tries again.
    func shutdown() {
        guard watchdog.setByHelper else { return }
        let value = flag.set(false, force: true)
        if !value, recoveryChecksLeft == 0 {
            watchdog.didClear()
            marker.remove()
        }
    }

    // The flag of an earlier run, or of a set that was not confirmed. False is written once whatever the kernel
    // reports, and the marker stays until the flag was off on every check.
    private func recover() -> Bool {
        // On again after the write: the checks start over.
        if recoveryWritten, flag.read() == true { recoveryChecksLeft = Self.recoveryChecks }
        let value = flag.set(false, force: !recoveryWritten)
        recoveryWritten = true
        if value {
            recoveryChecksLeft = Self.recoveryChecks
            return true
        }
        recoveryChecksLeft -= 1
        if recoveryChecksLeft == 0 {
            watchdog.didClear()
            marker.remove()
        }
        return false
    }

    // Ownership ends only when the kernel confirms the flag is off, so a
    // failed clear is tried again on the next tick.
    private func clear() -> Bool {
        let value = flag.set(false)
        if !value {
            watchdog.didClear()
            marker.remove()
        }
        return value
    }
}
