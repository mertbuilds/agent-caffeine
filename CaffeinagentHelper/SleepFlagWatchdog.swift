import Foundation

// Decides when the helper clears SleepDisabled on its own. Pure: the caller
// passes the time in and carries the actions out. The time is seconds on a
// clock that only moves forward, not the date: a change of the wall clock
// must neither clear the flag early nor keep it for longer.
struct SleepFlagWatchdog {
    enum Action: Equatable {
        case none
        case clearFlag
    }

    let timeout: TimeInterval
    // True from just before the helper sets the flag until a clear is
    // confirmed. Mirrors the marker file.
    private(set) var setByHelper: Bool
    private var deadline: TimeInterval?

    // A marker left by an earlier run means the flag outlived the helper
    // (reboot, crash), so the first tick clears it.
    init(markerExists: Bool, timeout: TimeInterval = 60) {
        self.timeout = timeout
        self.setByHelper = markerExists
        self.deadline = nil
    }

    mutating func willSet(now: TimeInterval) {
        setByHelper = true
        deadline = now + timeout
    }

    mutating func didClear() {
        setByHelper = false
        deadline = nil
    }

    mutating func heartbeat(now: TimeInterval) {
        guard setByHelper else { return }
        deadline = now + timeout
    }

    // A lost connection needs no event of its own: the heartbeats stop with
    // it, and one from a new connection within the timeout keeps the flag.
    func tick(now: TimeInterval) -> Action {
        guard setByHelper else { return .none }
        guard let deadline else { return .clearFlag }
        return now >= deadline ? .clearFlag : .none
    }
}
