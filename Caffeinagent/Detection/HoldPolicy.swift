import Foundation

/// Why one instance keeps the Mac awake.
enum HoldCause: Equatable {
    case working
    /// Waits for the user, and the waiting hold has not run out.
    case waitingForUser
    /// Went idle less than the release time ago.
    case finishedRecently
    /// Mode "while an agent is open" only.
    case open
}

struct AgentHold: Equatable {
    var reading: AgentReading
    /// Nil when this instance does not keep the Mac awake.
    var cause: HoldCause?
}

/// One agent by name, or several by count.
enum HoldSubject: Equatable {
    case one(String)
    case many(Int)

    init?(names: [String]) {
        guard let first = names.first else { return nil }
        self = names.count == 1 ? .one(first) : .many(names.count)
    }
}

/// What the decision comes to, in one case. The menu words it in
/// `MenuModel`, and `text` is the line of the lab log.
enum HoldHeadline: Equatable {
    case working(HoldSubject)
    case waitingHeld(HoldSubject)
    case finishedRecently(HoldSubject)
    case open(HoldSubject)
    case alwaysOn
    case remoteAccess
    /// The user asked the Mac to stay reachable until this time, and no
    /// agent keeps it awake.
    case reachable(until: Date)
    /// A hold from the command line keeps the Mac awake, and no agent
    /// does. The subject is what the holds are for, see `ManualHold.subject`.
    case manualHold(HoldSubject)
    case idle(HoldSubject)
    case waitingReleased(HoldSubject)
    case noAgents
    case safetyStop(SafetyStop)
    case switchedOff
    /// The user paused Agent Caffeine until this time.
    case paused(until: Date)
    case notEntitled(ExpiredReason)

    var keepsAwake: Bool {
        switch self {
        case .working, .waitingHeld, .finishedRecently, .open, .alwaysOn, .remoteAccess, .reachable, .manualHold: return true
        case .idle, .waitingReleased, .noAgents, .safetyStop, .switchedOff, .paused, .notEntitled: return false
        }
    }

    /// A safety stop, the switch, a pause or the license: the Mac can
    /// sleep whatever asks for a hold.
    var isStop: Bool {
        switch self {
        case .safetyStop, .switchedOff, .paused, .notEntitled: return true
        default: return false
        }
    }

    /// What keeps the Mac awake, as the power assertion says it. Nil when
    /// nothing does.
    var awakeReason: String? {
        switch self {
        case .working(let subject): return Self.phrase(subject, one: "is working", many: "are working")
        case .waitingHeld(let subject): return Self.phrase(subject, one: "is waiting for you", many: "are waiting for you")
        case .finishedRecently(let subject): return Self.phrase(subject, one: "finished a moment ago", many: "finished a moment ago")
        case .open(let subject): return Self.phrase(subject, one: "is open", many: "are open")
        case .alwaysOn: return "always on"
        case .remoteAccess: return "reachable while plugged in"
        case .reachable: return "stays reachable"
        case .manualHold(.one(let name)): return "\(name) asked for it"
        case .manualHold(.many(let count)): return "\(count) commands asked for it"
        case .idle, .waitingReleased, .noAgents, .safetyStop, .switchedOff, .paused, .notEntitled: return nil
        }
    }

    var text: String {
        switch self {
        case .working, .waitingHeld, .finishedRecently, .open, .alwaysOn, .remoteAccess, .reachable, .manualHold: return "Awake: \(awakeReason ?? "")"
        case .idle(.one(let name)): return "Mac can sleep: \(name) is idle"
        case .idle(.many): return "Mac can sleep: all agents are idle"
        case .waitingReleased(let subject): return "Mac can sleep: \(Self.phrase(subject, one: "is waiting for you", many: "are waiting for you"))"
        case .noAgents: return "Mac can sleep: no agent is open"
        case .safetyStop(.batteryLow(let percent)): return "Sleeping allowed: battery at \(PanelText.percent(percent))"
        case .safetyStop(.weakCharger(let percent)): return "Sleeping allowed: weak charger, battery at \(PanelText.percent(percent))"
        case .safetyStop(.tooHot): return "Sleeping allowed: the Mac is too hot"
        case .switchedOff: return "Mac can sleep: Agent Caffeine is off"
        case .paused: return "Mac can sleep: Agent Caffeine is paused"
        case .notEntitled(let reason): return reason.text
        }
    }

    private static func phrase(_ subject: HoldSubject, one: String, many: String) -> String {
        switch subject {
        case .one(let name): return "\(name) \(one)"
        case .many(let count): return "\(count) agents \(many)"
        }
    }
}

struct HoldDecision: Equatable {
    var hold: Bool
    /// Whether SleepDisabled has to be set, so the Mac also stays awake with
    /// the lid closed on battery.
    var lidClosedFlag: Bool
    var headline: HoldHeadline
    /// In the order of the readings.
    var perAgent: [AgentHold]
    /// When Agent Caffeine lets go, while it holds only for agents that
    /// wait for the user. Nil when anything else keeps the Mac awake: an
    /// agent that works, finished a moment ago or is open, the mode,
    /// "stay reachable", or phone access on power. See `SleepOutlook`.
    var waitingEnds: Date? = nil
    /// The holds from the command line whose time is not over, the oldest
    /// first. They are listed in a stop too, and keep nothing awake then.
    var manualHolds: [ManualHold] = []
}

struct PolicyMemory: Equatable {
    struct Instance: Equatable {
        var lastWorkingAt: Date?
        /// When the current wait for the user began.
        var waitingSince: Date?
    }

    var instances: [ProcessIdentity: Instance] = [:]
}

/// Decides whether the Mac stays awake. Pure: the caller keeps the memory
/// and passes the time. Each instance holds on its own, so one that stops
/// never releases the Mac while another still works.
enum HoldPolicy {
    static func decide(
        readings: [AgentReading], memory: PolicyMemory, mode: AwakeMode, enabled: Bool, pausedUntil: Date? = nil,
        reachableUntil: Date? = nil, holds: [ManualHold] = [],
        entitlement: Entitlement?, safety: SafetyStop?, settings: DetectionSettings, context: FrameContext, mayHold: Bool = true, now: Date
    ) -> (HoldDecision, PolicyMemory) {
        let memory = remember(readings, memory: memory, settings: settings, now: now)
        // The collector looked at the holders. The time is checked here
        // again, because a decision is also made between two samples.
        let manual = holds.filter { $0.isTimely(now: now) }
        let perAgent = readings.map { reading in
            AgentHold(reading: reading, cause: cause(of: reading, memory: memory, mode: mode, settings: settings, now: now))
        }
        if let stop = stopHeadline(enabled: enabled, pausedUntil: pausedUntil, entitlement: entitlement, safety: safety, now: now) {
            let released = perAgent.map { AgentHold(reading: $0.reading, cause: nil) }
            return (HoldDecision(hold: false, lidClosedFlag: false, headline: stop, perAgent: released, manualHolds: manual), memory)
        }
        let reachable = reachableUntil.flatMap { now < $0 ? $0 : nil }
        let headline = headline(perAgent, mode: mode, reachableUntil: reachable, manual: manual, settings: settings, context: context)
        let hold = headline.keepsAwake
        // Between the word that the Mac goes to sleep and the first sample
        // after its full wake nothing starts a hold. See `WakeGate`.
        if hold, !mayHold {
            let released = perAgent.map { AgentHold(reading: $0.reading, cause: nil) }
            return (
                HoldDecision(hold: false, lidClosedFlag: false, headline: restHeadline(released, settings: settings), perAgent: released, manualHolds: manual),
                memory
            )
        }
        // Set with the hold, also on wall power: unplugging with the lid
        // closed must not race the flag. With the setting off the power
        // assertions alone cover a closed lid on wall power.
        let lidClosedFlag = hold && settings.stayAwakeLidClosedOnBattery
        let staysAwake = mode != .agentWorking || reachable != nil || !manual.isEmpty || remoteAccessHolds(settings: settings, context: context)
        let waitingEnds = staysAwake ? nil : waitingEnds(perAgent, memory: memory, settings: settings)
        return (
            HoldDecision(hold: hold, lidClosedFlag: lidClosedFlag, headline: headline, perAgent: perAgent, waitingEnds: waitingEnds, manualHolds: manual),
            memory
        )
    }

    private static func remoteAccessHolds(settings: DetectionSettings, context: FrameContext) -> Bool {
        settings.stayAwakeForRemoteAccess && context.remoteAccessDetected && !context.onBattery
    }

    /// Nil when an agent holds for another cause, or none waits. An agent
    /// that reports its own state holds on as "finished a moment ago"
    /// after a short wait, so that end counts too.
    private static func waitingEnds(_ perAgent: [AgentHold], memory: PolicyMemory, settings: DetectionSettings) -> Date? {
        guard perAgent.allSatisfy({ $0.cause == nil || $0.cause == .waitingForUser }) else { return nil }
        return perAgent.filter { $0.cause == .waitingForUser }.compactMap { hold -> Date? in
            guard let instance = memory.instances[hold.reading.identity], let since = instance.waitingSince else { return nil }
            let waited = since.addingTimeInterval(settings.waitingHold)
            guard hold.reading.level == .state, let last = instance.lastWorkingAt else { return waited }
            return max(waited, last.addingTimeInterval(settings.releaseAfterState))
        }.max()
    }

    /// Safety comes first, then the switch, then a pause, then the
    /// license. A pause is the user's own word like the switch, so it is
    /// named before a license that ran out. It comes after the switch,
    /// because a pause of an app that is off means nothing. Every stop
    /// gives a decision without the sleep flag, so a pause never leaves
    /// SleepDisabled on. No entitlement means there is none to check.
    private static func stopHeadline(
        enabled: Bool, pausedUntil: Date?, entitlement: Entitlement?, safety: SafetyStop?, now: Date
    ) -> HoldHeadline? {
        if let safety { return .safetyStop(safety) }
        guard enabled else { return .switchedOff }
        if let pausedUntil, now < pausedUntil { return .paused(until: pausedUntil) }
        if case .expired(let reason)? = entitlement { return .notEntitled(reason) }
        return nil
    }

    /// An instance that is not among the readings is gone, and so is its hold.
    private static func remember(_ readings: [AgentReading], memory: PolicyMemory, settings: DetectionSettings, now: Date) -> PolicyMemory {
        var next = PolicyMemory()
        for reading in readings where settings.rule(for: reading.agentID) != .ignore {
            var instance = memory.instances[reading.identity] ?? PolicyMemory.Instance()
            switch reading.verdict.state {
            case .working:
                instance.lastWorkingAt = now
                instance.waitingSince = nil
            case .waitingForUser:
                instance.waitingSince = instance.waitingSince ?? now
            case .idle:
                instance.waitingSince = nil
            }
            next.instances[reading.identity] = instance
        }
        return next
    }

    /// The release time after work applies to agents that report their own
    /// state. For the others the verdict already counts the release time
    /// after the last sign of work.
    private static func cause(of reading: AgentReading, memory: PolicyMemory, mode: AwakeMode, settings: DetectionSettings, now: Date) -> HoldCause? {
        guard let instance = memory.instances[reading.identity] else { return nil }
        switch reading.verdict.state {
        case .working:
            return .working
        case .waitingForUser:
            if let since = instance.waitingSince, now.timeIntervalSince(since) < settings.waitingHold { return .waitingForUser }
        case .idle:
            break
        }
        if reading.level == .state, let last = instance.lastWorkingAt, now.timeIntervalSince(last) < settings.releaseAfterState {
            return .finishedRecently
        }
        if mode == .agentOpen, reading.kind == .cli || reading.hasLiveSession { return .open }
        return nil
    }

    /// An agent that keeps the Mac awake is named before a hold from the
    /// command line and before "stay reachable": its reason is the one
    /// that counts while it works.
    private static func headline(
        _ perAgent: [AgentHold], mode: AwakeMode, reachableUntil: Date?, manual: [ManualHold], settings: DetectionSettings, context: FrameContext
    ) -> HoldHeadline {
        if mode == .always { return .alwaysOn }
        func subject(_ cause: HoldCause) -> HoldSubject? {
            HoldSubject(names: perAgent.filter { $0.cause == cause }.map(\.reading.displayName))
        }
        if let working = subject(.working) { return .working(working) }
        if let waiting = subject(.waitingForUser) { return .waitingHeld(waiting) }
        if let finished = subject(.finishedRecently) { return .finishedRecently(finished) }
        if let open = subject(.open) { return .open(open) }
        if let asked = HoldSubject(names: manual.map(\.subject)) { return .manualHold(asked) }
        if let reachableUntil { return .reachable(until: reachableUntil) }
        if remoteAccessHolds(settings: settings, context: context) { return .remoteAccess }
        return restHeadline(perAgent, settings: settings)
    }

    /// What is said when nothing keeps the Mac awake.
    private static func restHeadline(_ perAgent: [AgentHold], settings: DetectionSettings) -> HoldHeadline {
        let counted = perAgent.map(\.reading).filter { settings.rule(for: $0.agentID) != .ignore }
        if let waiting = HoldSubject(names: counted.filter { $0.verdict.state == .waitingForUser }.map(\.displayName)) {
            return .waitingReleased(waiting)
        }
        return HoldSubject(names: counted.map(\.displayName)).map(HoldHeadline.idle) ?? .noAgents
    }
}
