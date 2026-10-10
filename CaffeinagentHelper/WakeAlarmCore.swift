import Foundation

// One entry of the system's list of scheduled power events, as
// `pmset -g sched` prints it.
struct WakeEvent: Equatable {
    // Kept as the date the system gave: a cancel must pass the same value.
    let date: Date
    let owner: String
    let type: String
}

// The system's list of scheduled power events. The owner and the type of
// what is scheduled and cancelled are fixed behind it, so the two calls take
// a time and nothing else and can never reach an event of someone else.
protocol WakeEventStoring {
    // Every event in the list, also the ones of macOS and of other apps.
    // Nil when the list could not be read. That is not an empty list: an
    // alarm of ours can be in it.
    func events() -> [WakeEvent]?
    func schedule(at date: Date) -> Bool
    func cancel(at date: Date) -> Bool
}

// Everything the helper decides about its one wake alarm, with the list of
// events and the two clocks passed in. Not thread safe: HelperService calls
// it on one queue.
//
// The rules:
// - The time is at least 20 seconds and at most 8 days ahead.
// - One alarm. A new time takes the place of the old one, the same time
//   again changes nothing, and more than one entry of ours becomes one.
// - Only entries with our owner name and the type "wake" are ours. Every
//   other entry is never cancelled and never changed.
// - After a schedule the list is read again. The alarm counts as set only
//   when the list shows it once.
// - At most 30 new times per hour.
// - The app asks again within 10 minutes of awake time, or the alarm goes.
// - The alarm goes 30 seconds of awake time after the last connection of
//   the app ended, unless a new one came.
// - The alarm goes when the helper stops, and at its start: the lease is
//   not kept across a restart, so an alarm found then has no one behind it.
//
// What is ours is read from the list on every call, never from memory.
// A list that cannot be read is not an empty list: the alarm counts as
// still there, a cancel answers "not cancelled", and the ticks go on.
final class WakeAlarmCore {
    // The name our event has in `pmset -g sched`. powerd makes a dark wake
    // for a name with "com.apple.alarm" in it; ours has none.
    static let owner = "com.caffeinagent.app.wake"
    // The value of kIOPMAutoWake. Never a power on.
    static let eventType = "wake"
    // The times are whole seconds, so half a second tells two apart.
    private static let sameTime: TimeInterval = 0.5
    private static let hour: TimeInterval = 3600
    // A cancel can take one of two equal entries or both, so the list is
    // read again and the rest cancelled, this many times at most.
    private static let cancelPasses = 3

    private let store: WakeEventStoring
    // Seconds since 1970, for the check of the time asked for.
    private let date: () -> TimeInterval
    // Seconds the Mac was awake, for the lease and the rate limit. See
    // HelperCore.awakeSeconds: time asleep does not count, so a Mac that
    // slept for hours does not lose its alarm at the wake.
    private let awake: () -> TimeInterval
    // Nil for no lease. A time that has passed means: take ours away at the
    // next tick, and again until the list has none.
    private var leaseEnds: TimeInterval?
    // The time this run of the helper scheduled last, until the list
    // shows that no entry of ours is left. Used only when the list cannot
    // be read: then this is the one time a cancel can be tried for.
    private var lastScheduled: TimeInterval?
    private var sets: [TimeInterval] = []
    private let clientGrace: TimeInterval
    // The connections of the app that are open.
    private var clients = 0
    // When the last of them ended, in awake seconds. Nil while one is
    // open, and before the first one.
    private var clientsGoneAt: TimeInterval?

    // The timer of the service runs while this is true.
    var needsTicks: Bool { leaseEnds != nil }

    init(
        store: WakeEventStoring,
        date: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        awake: @escaping () -> TimeInterval = HelperCore.awakeSeconds,
        clientGrace: TimeInterval = WakeAlarmLimits.clientGrace
    ) {
        self.store = store
        self.date = date
        self.awake = awake
        self.clientGrace = clientGrace
    }

    // The app opened a connection.
    func clientConnected() {
        clients += 1
        clientsGoneAt = nil
    }

    // A connection of the app ended. HelperService says it once for each.
    // After the last one the alarm has `clientGrace` left: see `tick`.
    func clientGone() {
        clients = max(clients - 1, 0)
        if clients == 0 { clientsGoneAt = awake() }
    }

    // How long after `clientGone` a tick is due.
    var graceAfterClients: TimeInterval { clientGrace }

    // An alarm in the list at the start of the helper is one of an earlier
    // run: a crash, a reboot, an app that was removed.
    func start() {
        removeOurs()
    }

    func set(at requested: TimeInterval) -> WakeAlarmResult {
        if requested == 0 {
            return removeOurs() ? .cancelled : .refused(.notCancelled)
        }
        // A refusal changes nothing: an alarm that is set stays, and its
        // lease is not made longer.
        guard requested.isFinite, requested > 0 else { return .refused(.notATime) }
        let time = requested.rounded()
        let ahead = time - date()
        guard ahead >= WakeAlarmLimits.minimumLead else { return .refused(.tooSoon) }
        guard ahead <= WakeAlarmLimits.maximumLead else { return .refused(.tooFar) }

        let now = awake()
        guard let mine = ours() else {
            unread()
            return .refused(.notCancelled)
        }
        if mine.count == 1, isSame(mine[0], time) {
            leaseEnds = now + WakeAlarmLimits.lease
            return .set(time)
        }

        sets.removeAll { now - $0 >= Self.hour }
        guard sets.count < WakeAlarmLimits.setsPerHour else { return .refused(.tooOften) }
        sets.append(now)

        guard removeOurs() else { return .refused(.notCancelled) }
        lastScheduled = time
        guard store.schedule(at: Date(timeIntervalSince1970: time)) else {
            // The call can fail and leave an entry all the same.
            removeOurs()
            return .refused(.notScheduled)
        }
        guard let listed = ours(), listed.count == 1, isSame(listed[0], time) else {
            removeOurs()
            return .refused(.notConfirmed)
        }
        leaseEnds = now + WakeAlarmLimits.lease
        return .set(time)
    }

    // Takes the alarm away when nobody is behind it:
    // - The app has no connection for `clientGrace`: it quit with no cancel,
    //   or died.
    // - The app did not ask again within the lease. This stays as the rule
    //   for an app that is connected and hangs.
    //
    // The bridge would go here: when the clock passes an alarm the helper
    // set, the helper sets SleepDisabled itself for at most 60 seconds, until
    // the app takes over. It is not built. Experiment E3 of the design note
    // decides it: with the lid closed on battery, can the app set the flag
    // through the helper before the Mac sleeps again after the alarm?
    func tick() {
        guard let leaseEnds else { return }
        let now = awake()
        if let clientsGoneAt, now - clientsGoneAt >= clientGrace {
            removeOurs()
        } else if now >= leaseEnds {
            removeOurs()
        }
    }

    // launchd stops the helper, or the app retires it. One try: the next
    // start takes away what is left.
    func shutdown() {
        removeOurs()
    }

    // Nil when the list could not be read.
    private func ours() -> [WakeEvent]? {
        store.events()?.filter { $0.owner == Self.owner && $0.type == Self.eventType }
    }

    private func isSame(_ event: WakeEvent, _ time: TimeInterval) -> Bool {
        abs(event.date.timeIntervalSince1970 - time) < Self.sameTime
    }

    // True when the list has no entry of ours after it. If one stays, or
    // the list cannot be read, the lease is set to "over", so every tick
    // tries again.
    @discardableResult
    private func removeOurs() -> Bool {
        for _ in 0..<Self.cancelPasses {
            guard let mine = ours() else { return unread() }
            if mine.isEmpty { break }
            for event in mine { _ = store.cancel(at: event.date) }
        }
        guard let left = ours() else { return unread() }
        let gone = left.isEmpty
        leaseEnds = gone ? nil : awake()
        if gone { lastScheduled = nil }
        return gone
    }

    // The list could not be read, so an alarm of ours can be in it. The
    // time that was scheduled last is cancelled blind. That is no proof
    // that nothing is left: the answer is false, and the ticks go on until
    // the list can be read again.
    @discardableResult
    private func unread() -> Bool {
        if let lastScheduled { _ = store.cancel(at: Date(timeIntervalSince1970: lastScheduled)) }
        leaseEnds = awake()
        return false
    }
}
