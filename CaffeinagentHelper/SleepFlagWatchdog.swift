import Foundation

// Decides when the helper clears SleepDisabled on its own. Pure: the caller
// passes the time in and carries the actions out.
struct SleepFlagWatchdog {
    enum Action: Equatable {
        case none
        case clearFlag
    }

    let timeout: TimeInterval
    // True from just before the helper sets the flag until a clear is
    // confirmed. Mirrors the marker file.
    private(set) var setByHelper: Bool
    private var deadline: Date?

    // A marker left by an earlier run means the flag outlived the helper
    // (reboot, crash), so the first tick clears it.
    init(markerExists: Bool, timeout: TimeInterval = 60) {
        self.timeout = timeout
        self.setByHelper = markerExists
        self.deadline = nil
    }

    mutating func willSet(now: Date) {
        setByHelper = true
        deadline = now.addingTimeInterval(timeout)
    }

    mutating func didClear() {
        setByHelper = false
        deadline = nil
    }

    mutating func heartbeat(now: Date) {
        guard setByHelper else { return }
        deadline = now.addingTimeInterval(timeout)
    }

    // A lost connection needs no event of its own: the heartbeats stop with
    // it, and one from a new connection within the timeout keeps the flag.
    func tick(now: Date) -> Action {
        guard setByHelper else { return .none }
        guard let deadline else { return .clearFlag }
        return now >= deadline ? .clearFlag : .none
    }
}
