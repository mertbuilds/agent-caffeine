import Foundation

/// Stored by name, so a recorded log stays readable and an enum that gets
/// reordered or extended does not change what old logs mean.
protocol NameCoded: Codable, Equatable {
    static var names: [(value: Self, name: String)] { get }
}

extension NameCoded {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let match = Self.names.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown \(Self.self) \(name)")
        }
        self = match.value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let match = Self.names.first(where: { $0.value == self }) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "No name for \(self)"))
        }
        try container.encode(match.name)
    }
}

extension ReportedState: NameCoded {
    static let names: [(value: ReportedState, name: String)] = [
        (.working, "working"), (.waitingForUser, "waiting"), (.idle, "idle"),
    ]
}

extension StateReport.Source: NameCoded {
    static let names: [(value: StateReport.Source, name: String)] = [
        (.claudeSessionFile, "claudeSession"), (.claudeJobState, "claudeJob"), (.claudeTranscript, "claudeTranscript"),
        (.codexRollout, "codexRollout"), (.cursorTranscript, "cursorTranscript"), (.grokEvents, "grokEvents"),
        (.hermesState, "hermesState"), (.openClawState, "openClawState"),
        (.fileActivity, "fileActivity"),
    ]
}

extension AgentDefinition.Level: NameCoded {
    static let names: [(value: AgentDefinition.Level, name: String)] = [
        (.state, "state"), (.activity, "activity"), (.generic, "generic"),
    ]
}

extension AgentDefinition.Kind: NameCoded {
    static let names: [(value: AgentDefinition.Kind, name: String)] = [(.cli, "cli"), (.desktop, "desktop")]
}

extension AgentRole: NameCoded {
    static let names: [(value: AgentRole, name: String)] = [
        (.session, "session"), (.engine, "engine"), (.helper, "helper"), (.helperMaybeSession, "maybeSession"),
    ]
}

extension StateReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case state, since, observedAt = "seen", source, detail, turnEnded = "over", failed = "err"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            state: try container.decode(ReportedState.self, forKey: .state),
            since: try container.decodeIfPresent(Date.self, forKey: .since),
            observedAt: try container.decode(Date.self, forKey: .observedAt),
            source: try container.decode(Source.self, forKey: .source),
            detail: try container.decodeIfPresent(String.self, forKey: .detail),
            turnEnded: try container.decodeIfPresent(Bool.self, forKey: .turnEnded) ?? false,
            failed: try container.decodeIfPresent(Bool.self, forKey: .failed) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(since, forKey: .since)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(detail, forKey: .detail)
        if turnEnded { try container.encode(true, forKey: .turnEnded) }
        if failed { try container.encode(true, forKey: .failed) }
    }
}

/// Everything seen about one agent instance at one instant. It holds signals
/// only, no judgement: `VerdictRules` turns it into a state.
///
/// One of these is logged per instance per second, so the keys are short, and
/// a count of zero or a false flag is left out and read back as the default.
struct AgentEvidence: Codable, Equatable {
    /// `AgentDefinition.id`.
    var agentID: String
    var displayName: String
    var level: AgentDefinition.Level
    var kind: AgentDefinition.Kind
    var role: AgentRole
    var pid: Int32
    /// Seconds since the epoch, as in `ProcessInfoRow`.
    var startTime: TimeInterval

    /// The agent's own state file or session log. Nil when there is none or
    /// it could not be read. `observedAt` says when it was read.
    var reported: StateReport?
    /// Claude job state files in the working state that belong to this session.
    var backgroundJobsWorking: Int
    /// Live descendants that are not the agent itself. For Cursor: the
    /// shells its agent started, counted only while a turn is in progress.
    var childCommands: Int
    /// The child commands that `VerdictRules.isBusyChild` accepts.
    var busyChildCommands: Int
    /// CPU seconds the whole subtree used since the previous sample.
    var subtreeCPUSeconds: Double
    /// Seconds since the previous sample. Zero on the first sample, and on
    /// the first one after a `SampleGap`.
    var sampleInterval: TimeInterval
    var energyNanojoules: UInt64?
    var logicalWriteBytes: UInt64?
    /// The last write to a session file.
    var fileActivityAt: Date?
    /// The agent, or a `caffeinate` child of it, holds a power assertion.
    /// For Cursor: its main process holds one, as it does from the prompt
    /// to the end of the answer. For the Claude app: its main process holds
    /// one, which is recorded and is no sign of work.
    var ownsSleepAssertion: Bool
    /// Desktop apps only: a session file was written in the last hour, or a
    /// task is not finished.
    var hasLiveSession: Bool
    /// From the optional hooks.
    var hookState: ReportedState?
    var hookStateAt: Date?
    /// The hook state was set against the agent's own log session by
    /// session: Cursor, where a hook session is a transcript
    /// (`HookStateFile.summary`). The verdict does not compare the time
    /// of the hook state with the time of the report again.
    var hookStateBySession: Bool

    init(
        agentID: String, displayName: String, level: AgentDefinition.Level, kind: AgentDefinition.Kind = .cli,
        role: AgentRole = .session, pid: Int32, startTime: TimeInterval,
        reported: StateReport? = nil, backgroundJobsWorking: Int = 0, childCommands: Int = 0, busyChildCommands: Int = 0,
        subtreeCPUSeconds: Double = 0, sampleInterval: TimeInterval = 0, energyNanojoules: UInt64? = nil,
        logicalWriteBytes: UInt64? = nil, fileActivityAt: Date? = nil, ownsSleepAssertion: Bool = false,
        hasLiveSession: Bool = false, hookState: ReportedState? = nil, hookStateAt: Date? = nil, hookStateBySession: Bool = false
    ) {
        self.agentID = agentID
        self.displayName = displayName
        self.level = level
        self.kind = kind
        self.role = role
        self.pid = pid
        self.startTime = startTime
        self.reported = reported
        self.backgroundJobsWorking = backgroundJobsWorking
        self.childCommands = childCommands
        self.busyChildCommands = busyChildCommands
        self.subtreeCPUSeconds = subtreeCPUSeconds
        self.sampleInterval = sampleInterval
        self.energyNanojoules = energyNanojoules
        self.logicalWriteBytes = logicalWriteBytes
        self.fileActivityAt = fileActivityAt
        self.ownsSleepAssertion = ownsSleepAssertion
        self.hasLiveSession = hasLiveSession
        self.hookState = hookState
        self.hookStateAt = hookStateAt
        self.hookStateBySession = hookStateBySession
    }

    var identity: ProcessIdentity { ProcessIdentity(pid: pid, startTime: startTime) }

    /// Share of one core the subtree used over the sample, nil on a first sample.
    var cpuFraction: Double? {
        sampleInterval > 0 ? subtreeCPUSeconds / sampleInterval : nil
    }

    /// How long ago the reported state was read.
    func reportAge(at now: Date) -> TimeInterval? {
        reported.map { now.timeIntervalSince($0.observedAt) }
    }

    private enum CodingKeys: String, CodingKey {
        case agentID = "id", displayName = "name", level, kind, role, pid, startTime = "start"
        case reported = "rep", backgroundJobsWorking = "jobs", childCommands = "cmds", busyChildCommands = "busy"
        case subtreeCPUSeconds = "cpu", sampleInterval = "dt", energyNanojoules = "nj", logicalWriteBytes = "wr"
        case fileActivityAt = "file", ownsSleepAssertion = "pwr", hasLiveSession = "live"
        case hookState = "hook", hookStateAt = "hookAt", hookStateBySession = "hookSes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentID = try container.decode(String.self, forKey: .agentID)
        displayName = try container.decode(String.self, forKey: .displayName)
        level = try container.decode(AgentDefinition.Level.self, forKey: .level)
        kind = try container.decodeIfPresent(AgentDefinition.Kind.self, forKey: .kind) ?? .cli
        role = try container.decodeIfPresent(AgentRole.self, forKey: .role) ?? .session
        pid = try container.decode(Int32.self, forKey: .pid)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        reported = try container.decodeIfPresent(StateReport.self, forKey: .reported)
        backgroundJobsWorking = try container.decodeIfPresent(Int.self, forKey: .backgroundJobsWorking) ?? 0
        childCommands = try container.decodeIfPresent(Int.self, forKey: .childCommands) ?? 0
        busyChildCommands = try container.decodeIfPresent(Int.self, forKey: .busyChildCommands) ?? 0
        subtreeCPUSeconds = try container.decodeIfPresent(Double.self, forKey: .subtreeCPUSeconds) ?? 0
        sampleInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? 0
        energyNanojoules = try container.decodeIfPresent(UInt64.self, forKey: .energyNanojoules)
        logicalWriteBytes = try container.decodeIfPresent(UInt64.self, forKey: .logicalWriteBytes)
        fileActivityAt = try container.decodeIfPresent(Date.self, forKey: .fileActivityAt)
        ownsSleepAssertion = try container.decodeIfPresent(Bool.self, forKey: .ownsSleepAssertion) ?? false
        hasLiveSession = try container.decodeIfPresent(Bool.self, forKey: .hasLiveSession) ?? false
        hookState = try container.decodeIfPresent(ReportedState.self, forKey: .hookState)
        hookStateAt = try container.decodeIfPresent(Date.self, forKey: .hookStateAt)
        hookStateBySession = try container.decodeIfPresent(Bool.self, forKey: .hookStateBySession) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentID, forKey: .agentID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(level, forKey: .level)
        if kind != .cli { try container.encode(kind, forKey: .kind) }
        if role != .session { try container.encode(role, forKey: .role) }
        try container.encode(pid, forKey: .pid)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(reported, forKey: .reported)
        if backgroundJobsWorking != 0 { try container.encode(backgroundJobsWorking, forKey: .backgroundJobsWorking) }
        if childCommands != 0 { try container.encode(childCommands, forKey: .childCommands) }
        if busyChildCommands != 0 { try container.encode(busyChildCommands, forKey: .busyChildCommands) }
        if subtreeCPUSeconds != 0 { try container.encode(subtreeCPUSeconds, forKey: .subtreeCPUSeconds) }
        if sampleInterval != 0 { try container.encode(sampleInterval, forKey: .sampleInterval) }
        try container.encodeIfPresent(energyNanojoules, forKey: .energyNanojoules)
        try container.encodeIfPresent(logicalWriteBytes, forKey: .logicalWriteBytes)
        try container.encodeIfPresent(fileActivityAt, forKey: .fileActivityAt)
        if ownsSleepAssertion { try container.encode(true, forKey: .ownsSleepAssertion) }
        if hasLiveSession { try container.encode(true, forKey: .hasLiveSession) }
        try container.encodeIfPresent(hookState, forKey: .hookState)
        try container.encodeIfPresent(hookStateAt, forKey: .hookStateAt)
        if hookStateBySession { try container.encode(true, forKey: .hookStateBySession) }
    }
}

/// What the Mac itself was doing when a frame was taken.
struct FrameContext: Codable, Equatable {
    var onBattery = false
    /// Nil on a Mac without a battery.
    var batteryPercent: Int?
    var lidClosed = false
    /// `ProcessInfo.ThermalState.rawValue`.
    var thermalState = ProcessInfo.ThermalState.nominal.rawValue
    /// Someone is connected over SSH or screen sharing.
    var remoteAccessDetected = false
    /// macOS says the battery charges. See `SafetyInputs.charging`.
    var charging = false

    init(onBattery: Bool = false, batteryPercent: Int? = nil, lidClosed: Bool = false,
         thermalState: Int = ProcessInfo.ThermalState.nominal.rawValue, remoteAccessDetected: Bool = false, charging: Bool = false) {
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.lidClosed = lidClosed
        self.thermalState = thermalState
        self.remoteAccessDetected = remoteAccessDetected
        self.charging = charging
    }

    /// An unknown thermal value reads as nominal.
    var safetyInputs: SafetyInputs {
        SafetyInputs(
            batteryPercent: batteryPercent,
            onBattery: onBattery,
            thermalState: ProcessInfo.ThermalState(rawValue: thermalState) ?? .nominal,
            charging: charging
        )
    }

    private enum CodingKeys: String, CodingKey {
        case onBattery = "bat", batteryPercent = "pct", lidClosed = "lid", thermalState = "heat", remoteAccessDetected = "remote", charging = "chg"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onBattery = try container.decodeIfPresent(Bool.self, forKey: .onBattery) ?? false
        batteryPercent = try container.decodeIfPresent(Int.self, forKey: .batteryPercent)
        lidClosed = try container.decodeIfPresent(Bool.self, forKey: .lidClosed) ?? false
        thermalState = try container.decodeIfPresent(Int.self, forKey: .thermalState) ?? ProcessInfo.ThermalState.nominal.rawValue
        remoteAccessDetected = try container.decodeIfPresent(Bool.self, forKey: .remoteAccessDetected) ?? false
        charging = try container.decodeIfPresent(Bool.self, forKey: .charging) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if onBattery { try container.encode(true, forKey: .onBattery) }
        try container.encodeIfPresent(batteryPercent, forKey: .batteryPercent)
        if lidClosed { try container.encode(true, forKey: .lidClosed) }
        if thermalState != ProcessInfo.ThermalState.nominal.rawValue { try container.encode(thermalState, forKey: .thermalState) }
        if remoteAccessDetected { try container.encode(true, forKey: .remoteAccessDetected) }
        if charging { try container.encode(true, forKey: .charging) }
    }
}

/// One line of the evidence log: every agent instance and the Mac's own
/// state at one instant. Replaying the frames through `VerdictRules` and
/// `HoldPolicy` gives the same decisions again.
struct EvidenceFrame: Codable, Equatable {
    /// Raised when a key changes its meaning. Added keys need no new version.
    static let currentVersion = 1

    var version = EvidenceFrame.currentVersion
    var at: Date
    /// Seconds the Mac was awake since boot, read with `at`. See `SampleGap`.
    var awake: TimeInterval?
    var agents: [AgentEvidence]
    var context: FrameContext
    /// The holds from the command line whose holder lives. Left out of a
    /// line with none.
    var holds: [ManualHold] = []
    /// The job holds of "Wake for jobs" that are open. Left out of a
    /// line with none. The engine adds them: the collector does not
    /// know them.
    var jobHolds: [JobHold] = []
    /// The time of the wake alarm that is set, in seconds since the
    /// epoch. Left out of a line with none.
    var wakeAlarm: TimeInterval?

    init(at: Date, agents: [AgentEvidence], context: FrameContext = FrameContext(), holds: [ManualHold] = []) {
        self.at = at
        self.agents = agents
        self.context = context
        self.holds = holds
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v", at, awake = "up", agents, context = "ctx", holds, jobHolds = "jobs", wakeAlarm = "alarm"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? EvidenceFrame.currentVersion
        at = try container.decode(Date.self, forKey: .at)
        awake = try container.decodeIfPresent(TimeInterval.self, forKey: .awake)
        agents = try container.decodeIfPresent([AgentEvidence].self, forKey: .agents) ?? []
        context = try container.decodeIfPresent(FrameContext.self, forKey: .context) ?? FrameContext()
        holds = try container.decodeIfPresent([ManualHold].self, forKey: .holds) ?? []
        jobHolds = try container.decodeIfPresent([JobHold].self, forKey: .jobHolds) ?? []
        wakeAlarm = try container.decodeIfPresent(TimeInterval.self, forKey: .wakeAlarm)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(at, forKey: .at)
        try container.encodeIfPresent(awake, forKey: .awake)
        try container.encode(agents, forKey: .agents)
        try container.encode(context, forKey: .context)
        if !holds.isEmpty { try container.encode(holds, forKey: .holds) }
        if !jobHolds.isEmpty { try container.encode(jobHolds, forKey: .jobHolds) }
        try container.encodeIfPresent(wakeAlarm, forKey: .wakeAlarm)
    }
}
