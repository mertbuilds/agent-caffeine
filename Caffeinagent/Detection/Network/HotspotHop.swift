import Foundation

/// "Join your iPhone hotspot": when the Mac loses its way to the network
/// while an agent works, it joins the hotspot the user named, so the
/// agent stays online. Off until the user switches it on.
///
/// When it joins. All of these hold: the feature is on, a hotspot is set
/// up, the Mac stays awake for an agent (`agentHolds`), no stop is in
/// force, and the Mac had no way to the network for `lostTime` of awake
/// time without a break. A hold from the command line, a scheduled job,
/// "stay reachable" and the mode "always" start no join by themselves:
/// they do not say that anything needs the network.
///
/// It never joins while the Mac has a way to the network, so it never
/// leaves a network that works for the hotspot. `HotspotJob` asks once
/// more right before the join.
///
/// How often. The first try comes when the lost time is over, the next
/// ones `retryDelays` after the try before, then one every `retryEvery`,
/// for as long as the agents count. The offline rule runs on as it is
/// (`OfflineRule`): after its limit the agents count no more, the tries
/// end and the Mac can sleep. A password the hotspot refused
/// `passwordTries` times is not tried again until the user saves again.
///
/// What it cannot do. An iPhone shows its hotspot for about 90 seconds
/// after the last device left, and only macOS itself can wake it, over
/// Bluetooth. A scan may find nothing: the state says "not found" then.
/// "Joined" means the Mac is on the hotspot, not that the phone has a
/// way to the internet.
///
/// The way back. The Wi-Fi the Mac was on when the way was lost is kept
/// in memory, and nowhere else. While the Mac is on the hotspot it looks
/// for that network every `backInterval`, and every `backIntervalInBag`
/// on battery with the lid closed: a scan takes the radio off its
/// channel for a moment and costs charge, and in a bag the old network
/// rarely comes back. When the network is seen, the Mac joins it with
/// no password, because macOS keeps that one. Only a network that macOS
/// knows as one with a WPA2 or WPA3 password counts, by its name to the
/// letter: an open network and one that asks for a user name get no way
/// back. This is tried once: when macOS refuses, the Mac stays on the
/// hotspot. A network the user left
/// before the way was lost is never joined: only the one of the last
/// look counts, and a look is at most `lookInterval` old.
///
/// Pure: the caller passes each sample and runs each action, and says
/// how it ended. No name leaves this value but inside an `Action`.
struct HotspotHop: Equatable {
    /// Awake seconds with no way to the network before the first try.
    /// Short breaks of a Wi-Fi are over by then.
    static let lostTime: TimeInterval = 15
    /// The wait after the first, the second and the third try.
    static let retryDelays: [TimeInterval] = [10, 20, 40]
    /// The wait after every later try.
    static let retryEvery: TimeInterval = 60
    /// After a join the path needs a moment: the Mac asks the phone for
    /// an address first. No new try before that.
    static let joinSettleTime: TimeInterval = 20
    /// While an agent works online, the name of the Wi-Fi is read this
    /// often.
    static let lookInterval: TimeInterval = 5
    static let backInterval: TimeInterval = 120
    static let backIntervalInBag: TimeInterval = 600
    static let passwordTries = 2

    /// What Settings, the menu and the state for the tests show.
    enum State: Equatable {
        /// Nothing happened yet, or the Mac left the hotspot.
        case idle
        /// The way to the network is lost, and the lost time runs.
        case waiting
        /// A try runs: a scan, then the join.
        case scanning
        case joined(at: Date)
        /// The phone did not show its hotspot at the last try.
        case notFound(at: Date)
        case failed(HopFailure, at: Date)
        /// The Mac went back to the Wi-Fi it had lost.
        case hoppedBack(at: Date)
    }

    /// What one sample says.
    struct Input: Equatable {
        /// The switch of the feature.
        var on = false
        /// The name of the hotspot. Nil while none is set up.
        var name: String?
        /// How often the user saved a name and a password. A new save
        /// gives a refused password its tries back.
        var saves = 0
        var hopBack = true
        /// See `HotspotHop.agentHolds`.
        var agentHolds = false
        /// A safety stop, the switch or a pause is in force.
        var stopped = false
        /// `NetworkPath.isOnline`.
        var online = true
        /// The user refused Location Services for Agent Caffeine.
        var permissionDenied = false
        var lidClosed = false
        var onBattery = false
    }

    /// Work for the caller, off the main thread. See `HotspotJob`.
    enum Action: Equatable {
        /// Read the name of the Wi-Fi the Mac is on.
        case look
        /// Scan for the hotspot and join it.
        case join(name: String)
        /// On the hotspot: is the Mac still on it, and is the old
        /// network back. `to` nil only asks the first.
        case back(hotspot: String, to: String?)
    }

    enum Outcome: Equatable {
        case network(String?)
        case joined
        case notFound
        case failed(HopFailure)
        /// A way to the network came back before the join. Nothing was
        /// joined.
        case pathBack
        case onHotspot
        /// The Mac is on another network, or on none.
        case leftHotspot
        case wentBack
        /// The old network was seen and macOS did not join it.
        case backFailed
    }

    private(set) var state = State.idle
    /// The action that runs. No second one starts before it ended.
    private(set) var pending: Action?
    /// Counts the awake time with no path, as the offline rule does.
    private var lost = OfflineRule()
    private var active = false
    private var online = true
    private var hotspot: String?
    private var saves: Int?
    private var passwordFailures = 0
    private var tries = 0
    private var nextTryAt: TimeInterval?
    /// The way was lost while an agent held the Mac awake. When it comes
    /// back, one look says whether the Mac is on the hotspot: macOS can
    /// join it by itself.
    private var lostWhileArmed = false
    private var checkHotspot = false
    /// The Wi-Fi of the last look, while it is not the hotspot.
    private var lastNetwork: String?
    private var lookedAt: TimeInterval?
    /// Where the way back goes.
    private var backTo: String?
    private var lastBackAt: TimeInterval?

    /// The Mac stays awake because an agent works, waits for the user or
    /// finished a moment ago. An agent that is only open does not count,
    /// and nothing else that keeps the Mac awake does.
    static func agentHolds(_ decision: HoldDecision) -> Bool {
        decision.hold && decision.perAgent.contains { hold in
            switch hold.cause {
            case .working, .waitingForUser, .finishedRecently: return true
            case .open, nil: return false
            }
        }
    }

    /// The awake clock where the sample has it, so a sleep counts for
    /// no wait.
    private static func clock(_ time: SampleTime) -> TimeInterval {
        time.awake ?? time.at.timeIntervalSince1970
    }

    /// One sample. The action that comes back is `pending` until
    /// `finished` is called for it.
    mutating func update(_ input: Input, at time: SampleTime) -> Action? {
        let now = Self.clock(time)
        lost.update(offline: !input.online, at: time)
        online = input.online
        if saves != input.saves {
            saves = input.saves
            passwordFailures = 0
            nextTryAt = nil
        }
        guard input.on, let name = HotspotName.cleaned(input.name) else {
            forget()
            return nil
        }
        // What was found out about another hotspot says nothing of this one.
        if let hotspot, !HotspotName.matches(hotspot, name) { forget() }
        active = true
        hotspot = name
        guard pending == nil else { return nil }
        if input.stopped {
            rest()
            return nil
        }
        return input.online ? onlineStep(input, name: name, now: now) : offlineStep(input, name: name, at: time)
    }

    private mutating func onlineStep(_ input: Input, name: String, now: TimeInterval) -> Action? {
        tries = 0
        nextTryAt = nil
        if case .joined = state { return backStep(input, name: name, now: now) }
        if state == .waiting { state = .idle }
        if lostWhileArmed {
            lostWhileArmed = false
            checkHotspot = true
            return start(.look)
        }
        guard input.agentHolds else {
            // Nothing is read while no agent works, and what was read
            // before is old by the time one does.
            lastNetwork = nil
            lookedAt = nil
            return nil
        }
        if let lookedAt, now >= lookedAt, now - lookedAt < Self.lookInterval { return nil }
        return start(.look)
    }

    private mutating func offlineStep(_ input: Input, name: String, at time: SampleTime) -> Action? {
        let now = Self.clock(time)
        guard input.agentHolds else {
            rest()
            return nil
        }
        lostWhileArmed = true
        guard let lostFor = lost.offlineFor, lostFor >= Self.lostTime else {
            state = .waiting
            tries = 0
            nextTryAt = nil
            return nil
        }
        if input.permissionDenied {
            if case .failed(.noPermission, _) = state { return nil }
            state = .failed(.noPermission, at: time.at)
            return nil
        }
        if passwordFailures >= Self.passwordTries { return nil }
        if let nextTryAt, now < nextTryAt { return nil }
        state = .scanning
        return start(.join(name: name))
    }

    /// On the hotspot, and online.
    private mutating func backStep(_ input: Input, name: String, now: TimeInterval) -> Action? {
        let every = input.lidClosed && input.onBattery ? Self.backIntervalInBag : Self.backInterval
        if let lastBackAt, now >= lastBackAt, now - lastBackAt < every { return nil }
        lastBackAt = now
        return start(.back(hotspot: name, to: input.hopBack ? backTo : nil))
    }

    private mutating func start(_ action: Action) -> Action {
        pending = action
        return action
    }

    /// How the pending action ended.
    mutating func finished(_ action: Action, _ outcome: Outcome, at time: SampleTime) {
        guard pending == action else { return }
        pending = nil
        // The feature went off while the action ran.
        guard active, let hotspot else { return }
        let now = Self.clock(time)
        switch (action, outcome) {
        case (.look, .network(let name)):
            lookedAt = now
            let check = checkHotspot
            checkHotspot = false
            // A look that ended after the way was lost says nothing of
            // the network before it.
            guard online else { return }
            if check, let name, HotspotName.matches(name, hotspot) {
                joined(at: time.at, now: now)
                return
            }
            lastNetwork = name.flatMap { HotspotName.matches($0, hotspot) ? nil : $0 }
        case (.join, .joined):
            joined(at: time.at, now: now)
            nextTryAt = now + Self.joinSettleTime
        case (.join, .notFound):
            tried(now: now)
            state = .notFound(at: time.at)
        case (.join, .failed(let failure)):
            tried(now: now)
            if failure == .wrongPassword { passwordFailures += 1 }
            state = .failed(failure, at: time.at)
        case (.join, .pathBack):
            if state == .scanning { state = .idle }
        case (.back, .leftHotspot):
            state = .idle
            backTo = nil
            lastNetwork = nil
        case (.back, .wentBack):
            state = .hoppedBack(at: time.at)
            backTo = nil
            lastNetwork = nil
        case (.back, .backFailed):
            // Once is enough: a join that fails can cost the hotspot too.
            backTo = nil
            lastNetwork = nil
        default:
            break
        }
    }

    private mutating func joined(at date: Date, now: TimeInterval) {
        state = .joined(at: date)
        backTo = lastNetwork
        lastBackAt = now
        passwordFailures = 0
        lostWhileArmed = false
    }

    private mutating func tried(now: TimeInterval) {
        let wait = tries < Self.retryDelays.count ? Self.retryDelays[tries] : Self.retryEvery
        tries += 1
        nextTryAt = now + wait
    }

    /// No try and no count goes on. What the last try came to stays.
    private mutating func rest() {
        if state == .waiting { state = .idle }
        tries = 0
        nextTryAt = nil
        lostWhileArmed = false
    }

    /// The feature is off or has no hotspot: nothing is kept, no name
    /// and no result.
    private mutating func forget() {
        let (pending, lost, saves, online) = (pending, lost, saves, online)
        self = HotspotHop()
        self.pending = pending
        self.lost = lost
        self.saves = saves
        self.online = online
    }
}

extension HotspotHop.State {
    /// For the state of the tests. The kind alone, with no name.
    var code: String {
        switch self {
        case .idle: return "idle"
        case .waiting: return "waiting"
        case .scanning: return "scanning"
        case .joined: return "joined"
        case .notFound: return "notFound"
        case .failed(let failure, _): return "failed:\(failure.rawValue)"
        case .hoppedBack: return "hoppedBack"
        }
    }

    /// When the last try ended. Nil while none did.
    var since: Date? {
        switch self {
        case .idle, .waiting, .scanning: return nil
        case .joined(let at), .notFound(let at), .failed(_, let at), .hoppedBack(let at): return at
        }
    }
}
