import Foundation

/// What the app knows at one moment, as its own types. `TestState` is
/// made from it, and takes kinds and times alone.
struct TestStateInput {
    var at: Date
    var version: String
    var build: String
    var bundlePath: String
    var pid: Int32
    var enabled: Bool
    var pausedUntil: Date?
    var reachableUntil: Date?
    var mode: AwakeMode
    var decision: HoldDecision
    /// The last sample, nil before the first one.
    var frame: EvidenceFrame?
    var assertionHeld: Bool
    var helper: HelperStatus
    var setup: HelperSetup
    var flagSet: Bool
    var lidAngle: Double?
    var safety: SafetyStop?
    /// The closed lid limit, with its period and the limits in use.
    var closedLid = ClosedLidLimit()
    /// The offline rule, with its count and the limit in use.
    var offline = OfflineRule()
    var gate: String
    var wakeForJobs: Bool
    var jobs: JobWakeView
    var notices: [TestState.Event] = []
    var chimeAt: Date?
}

/// The last notifications the app sent, the newest first.
struct TestNoticeLog: Equatable {
    static let length = 10

    private(set) var events: [TestState.Event] = []

    mutating func note(_ kind: TestNoticeKind, at: Date) {
        events.insert(TestState.Event(kind: kind.rawValue, at: at.timeIntervalSince1970), at: 0)
        if events.count > Self.length { events.removeLast(events.count - Self.length) }
    }
}

extension TestState {
    static let historyLength = 20
    private static let catalogIDs = Set(AgentCatalog.standard.definitions.map(\.id))

    init(_ input: TestStateInput) {
        let decision = input.decision
        let context = input.frame?.context
        var roles: [Int32: AgentRole] = [:]
        for agent in input.frame?.agents ?? [] { roles[agent.pid] = agent.role }
        self.init(
            at: input.at.timeIntervalSince1970,
            app: App(version: input.version, build: input.build, path: input.bundlePath, pid: input.pid),
            on: input.enabled,
            pausedUntil: input.pausedUntil?.timeIntervalSince1970,
            reachableUntil: input.reachableUntil?.timeIntervalSince1970,
            mode: input.mode.rawValue,
            decision: Decision(
                hold: decision.hold, headline: decision.headline.code, reason: decision.headline.reasonCode,
                stop: decision.headline.isStop, assertion: input.assertionHeld
            ),
            flag: Flag(wanted: decision.lidClosedFlag, helper: input.helper.code, setup: input.setup.code, set: input.flagSet),
            power: context.map { Power(source: $0.onBattery ? "battery" : "ac", percent: $0.batteryPercent, charging: $0.charging) },
            lid: context.map { Lid(closed: $0.lidClosed, angle: input.lidAngle.map { ($0 * 10).rounded() / 10 }) },
            safety: input.safety?.code,
            closedLid: input.closedLid.period.map { period in
                ClosedLid(
                    since: period.since.timeIntervalSince1970, heldSeconds: period.held.rounded(), percentAtStart: period.percentAtStart,
                    limitSeconds: input.closedLid.timeLimit, limitDrop: input.closedLid.dropLimit, stop: period.stop?.code,
                    agentsReleased: period.stop != nil
                )
            },
            network: context.map {
                Network(
                    online: !$0.offline, offlineSeconds: input.offline.offlineFor?.rounded(), limitSeconds: input.offline.limit,
                    agentsReleased: input.offline.agentsReleased
                )
            },
            gate: input.gate,
            agents: decision.perAgent.map { hold in
                let reading = hold.reading
                return Agent(
                    id: Self.catalogIDs.contains(reading.agentID) ? reading.agentID : Self.userAgentID,
                    pid: reading.identity.pid, role: roles[reading.identity.pid]?.code, state: reading.verdict.state.code,
                    why: reading.verdict.reason.code, level: reading.level.code, hold: hold.cause?.code
                )
            },
            holds: decision.manualHolds.map { Hold(id: $0.id, kind: $0.kind.rawValue, start: $0.start, end: $0.end) },
            jobs: Jobs(
                on: input.wakeForJobs, status: input.jobs.status.code,
                found: input.jobs.runs.count, enabled: input.jobs.runs.filter(\.job.enabled).count,
                alarm: input.jobs.alarm.map { alarm in
                    Alarm(
                        at: alarm.at.timeIntervalSince1970, fireAt: alarm.fireAt.timeIntervalSince1970,
                        source: input.jobs.runs.first { $0.job.id == alarm.jobID }?.job.source.rawValue
                    )
                },
                holds: decision.jobHolds.map { JobHoldRow(source: $0.source.rawValue, start: $0.start, fireAt: $0.fireAt, end: $0.end) },
                history: input.jobs.history.prefix(Self.historyLength).map { Event(kind: $0.kind.rawValue, at: $0.at) }
            ),
            notices: input.notices,
            chimeAt: input.chimeAt?.timeIntervalSince1970
        )
    }
}

private func name<Value: NameCoded>(of value: Value) -> String {
    Value.names.first { $0.value == value }?.name ?? "unknown"
}

private extension ReportedState {
    var code: String { name(of: self) }
}

private extension AgentRole {
    var code: String { name(of: self) }
}

private extension AgentDefinition.Level {
    var code: String { name(of: self) }
}

extension SafetyStop {
    var code: String {
        switch self {
        case .batteryLow: return "batteryLow"
        case .weakCharger: return "weakCharger"
        case .tooHot: return "tooHot"
        }
    }
}

extension ClosedLidStop {
    var code: String {
        switch self {
        case .time: return "closedLidTime"
        case .drop: return "closedLidDrop"
        }
    }
}

extension HelperStatus {
    var code: String {
        switch self {
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .enabled: return "enabled"
        case .notFound: return "notFound"
        }
    }
}

extension HelperSetup {
    var code: String {
        switch self {
        case .notSetUp: return "notSetUp"
        case .requiresApproval: return "requiresApproval"
        case .ready: return "ready"
        case .repairing: return "repairing"
        case .notResponding: return "notResponding"
        case .lost: return "lost"
        }
    }
}

extension JobWakeStatus {
    var code: String {
        switch self {
        case .off: return "off"
        case .needsApplications: return "needsApplications"
        case .needsHelper: return "needsHelper"
        case .helperSilent: return "helperSilent"
        case .noAlarm: return "noAlarm"
        case .asking: return "asking"
        case .alarmSet: return "alarmSet"
        case .refused: return "refused"
        }
    }
}

extension HoldHeadline {
    /// The case alone, with no name of an agent, a command or a job.
    var code: String {
        switch self {
        case .working: return "working"
        case .waitingHeld: return "waitingHeld"
        case .finishedRecently: return "finishedRecently"
        case .open: return "open"
        case .alwaysOn: return "alwaysOn"
        case .remoteAccess: return "remoteAccess"
        case .reachable: return "reachable"
        case .manualHold: return "manualHold"
        case .scheduledJob: return "scheduledJob"
        case .idle: return "idle"
        case .waitingReleased: return "waitingReleased"
        case .noAgents: return "noAgents"
        case .agentsStopped: return "agentsStopped"
        case .safetyStop: return "safetyStop"
        case .switchedOff: return "switchedOff"
        case .paused: return "paused"
        }
    }

    var reasonCode: String? {
        switch self {
        case .safetyStop(let stop): return stop.code
        case .agentsStopped(.offline): return "offline"
        case .agentsStopped(.closedLid(let stop)): return stop.code
        default: return nil
        }
    }
}
