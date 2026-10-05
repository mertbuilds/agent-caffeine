import Foundation

protocol SleepFlagAccessing {
    // nil when the kernel value cannot be read.
    func read() -> Bool?
    // Writes, reads back and retries. Returns the value the kernel reports,
    // or the opposite of `on` when it cannot be confirmed.
    func set(_ on: Bool) -> Bool
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
    private let now: () -> Date
    private var watchdog: SleepFlagWatchdog

    var setByHelper: Bool { watchdog.setByHelper }
    var sleepDisabled: Bool { flag.read() ?? false }

    init(flag: SleepFlagAccessing, marker: MarkerStoring, timeout: TimeInterval = 60, now: @escaping () -> Date = Date.init) {
        self.flag = flag
        self.marker = marker
        self.now = now
        self.watchdog = SleepFlagWatchdog(markerExists: marker.exists, timeout: timeout)
    }

    func setSleepDisabled(_ on: Bool) -> Bool {
        guard on else {
            // A flag someone else set is theirs to clear.
            return watchdog.setByHelper ? clear() : sleepDisabled
        }
        if !watchdog.setByHelper {
            // Already on without us: leave it alone and take no ownership.
            if flag.read() == true { return true }
            // The marker goes first, so a crash right after the set still
            // leaves it. Without a marker the flag could never be cleaned up.
            guard marker.write() else { return false }
        }
        watchdog.willSet(now: now())
        if flag.set(true) { return true }
        return clear()
    }

    func heartbeat() -> Bool {
        watchdog.heartbeat(now: now())
        return sleepDisabled
    }

    func tick() {
        if watchdog.tick(now: now()) == .clearFlag { _ = clear() }
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
