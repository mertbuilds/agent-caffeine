import Foundation

/// The one vocabulary for what an agent is doing. It is the same three
/// states the agents report about themselves, so a reported state needs no
/// mapping.
typealias WorkState = ReportedState

struct AgentVerdict: Equatable {
    enum Confidence: Equatable {
        /// The agent said so itself (state file, session log or hook), or
        /// the user's rule decides.
        case reported
        /// A sign that only work produces: a busy command, a background
        /// job, a sleep assertion of its own, a session-file write.
        case inferredStrong
        /// CPU use alone, or no sign at all.
        case inferredWeak
    }

    var state: WorkState
    var confidence: Confidence
    var reason: VerdictReason
}

enum VerdictReason: Equatable {
    case reportsBusy
    case runningCommand(Int)
    case backgroundJob(Int)
    case holdsSleepAssertion
    case writingSessionFile(secondsAgo: Int)
    /// A command, a background job or a sleep assertion ended a short time ago.
    case workedRecently(secondsAgo: Int)
    case cpuActivity
    case asksPermission
    case atPrompt
    case noActivity(minutes: Int)
    /// CPU use was the only sign for longer than the cap.
    case onlyWeakSigns(minutes: Int)
    case alwaysWorkingByRule
    case ignoredByRule

    /// The evidence in one line. The menu shows it when the pointer rests
    /// on an agent.
    var text: String {
        switch self {
        case .reportsBusy: return "Working on a task"
        case .runningCommand(let count): return "Running \(Self.counted(count, "command"))"
        case .backgroundJob(let count): return "Running \(Self.counted(count, "background task"))"
        case .holdsSleepAssertion: return "Asking your Mac to stay awake"
        case .writingSessionFile(let seconds): return "Wrote to its session \(Self.ago(seconds))"
        case .workedRecently(let seconds): return "Last worked \(Self.ago(seconds))"
        case .cpuActivity: return "Using the processor"
        case .asksPermission: return "Waiting for your answer"
        case .atPrompt: return "Ready for your next message"
        case .noActivity(let minutes): return ["No activity", HumaneDuration.lasting(minutes: minutes)].compactMap { $0 }.joined(separator: " ")
        case .onlyWeakSigns(let minutes):
            return ["Using the processor", HumaneDuration.lasting(minutes: minutes), "with no other sign of work"].compactMap { $0 }.joined(separator: " ")
        case .alwaysWorkingByRule: return "You set this agent to always count as working"
        case .ignoredByRule: return "You set agent caffeine to ignore this agent"
        }
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        HumaneDuration.counted(count, noun)
    }

    private static func ago(_ seconds: Int) -> String {
        HumaneDuration.ago(seconds: TimeInterval(seconds))
    }
}

/// What has to last from one sample to the next for one agent instance.
struct AgentMemory: Equatable {
    struct CPUSample: Equatable {
        var at: Date
        var cpuSeconds: Double
        var interval: TimeInterval
    }

    var firstSeenAt: Date?
    var lastCommandAt: Date?
    var lastBackgroundJobAt: Date?
    var lastAssertionAt: Date?
    var lastFileWriteAt: Date?
    /// The last time the CPU rule held, not the last hot sample.
    var lastCPUAt: Date?
    /// When CPU use became the only sign of work.
    var weakOnlySince: Date?
    /// Set when the cap ran out. A strong sign clears it, and so does a
    /// quiet stretch as long as the cap.
    var weakCapped = false
    var lastReport: StateReport?
    var lastReportSeenAt: Date?
    /// The time of the hook wait that ended on a sign of new work. That
    /// wait is not read again.
    var endedHookWaitAt: Date?
    /// The samples of the last `cpuWindow * cpuWindowCount` seconds.
    var cpuSamples: [CPUSample] = []

    var lastStrongAt: Date? {
        [lastCommandAt, lastBackgroundJobAt, lastAssertionAt, lastFileWriteAt].compactMap { $0 }.max()
    }
}

/// An instance together with its verdict: what `HoldPolicy` decides on.
struct AgentReading: Equatable {
    var agentID: String
    var displayName: String
    var level: AgentDefinition.Level
    var kind: AgentDefinition.Kind
    var identity: ProcessIdentity
    var hasLiveSession: Bool
    var verdict: AgentVerdict
    /// What the agent says of its own turn. Nil when it says nothing. The
    /// verdict can be working after the turn ended, for a command or a
    /// background job that still runs. The notifications follow the turn.
    var turn: AgentTurn?

    init(agentID: String, displayName: String, level: AgentDefinition.Level, kind: AgentDefinition.Kind = .cli,
         identity: ProcessIdentity, hasLiveSession: Bool = false, verdict: AgentVerdict, turn: AgentTurn? = nil) {
        self.agentID = agentID
        self.displayName = displayName
        self.level = level
        self.kind = kind
        self.identity = identity
        self.hasLiveSession = hasLiveSession
        self.verdict = verdict
        self.turn = turn
    }

    init(evidence: AgentEvidence, verdict: AgentVerdict, turn: AgentTurn? = nil) {
        self.init(agentID: evidence.agentID, displayName: evidence.displayName, level: evidence.level, kind: evidence.kind,
                  identity: evidence.identity, hasLiveSession: evidence.hasLiveSession, verdict: verdict, turn: turn)
    }
}

/// The turn of an agent that reports its own state.
struct AgentTurn: Equatable {
    var state: WorkState
    /// When the turn began, when the agent says so. Working only.
    var since: Date?
}

/// Turns evidence into a state. Pure: the caller keeps the memory and
/// passes the time.
///
/// The sources, most trusted first:
/// 1. a fresh hook state, or a hook wait of any age that has not ended,
/// 2. the reported state (state file or session log),
/// 3. strong signs: a busy command, a working background job, a sleep
///    assertion of the agent's own, a session-file write,
/// 4. weak signs: CPU use.
/// A hook idle does not beat a reported working.
/// A reported state beats weak signs in both directions. A reported idle or
/// waiting does not beat a busy command or a working background job: a turn
/// that ended is not work that ended.
enum VerdictRules {
    // All numbers below are from docs/research/04-experiments.md, 5 second
    // windows, percent of one core.
    //
    // CPU is weak evidence only. The old rule (3 percent in one window)
    // missed 45 percent of busy Claude windows and still flagged 2.5 percent
    // of idle ones. At 2 percent the sweep missed 0 percent of busy windows
    // (busy was 2.0 to 12.2) and flagged 4.9 percent of idle windows, so one
    // window proves nothing and the rule asks for 3 hot windows of the last
    // 6 (30 seconds). Idle windows had median 0.4 and p90 0.6; opencode
    // streamed text at 14.2 to 15.1. A start-up burst (48 to 125 percent,
    // seen for about a second) fills at most 2 windows and does not count.
    //
    // CPU cannot see a quiet tool call or a model wait on any agent (Codex
    // 0.0 to 1.9, opencode 0.4 to 1.1, claude -p 0.5 to 1.5). Those are held
    // by the reported state, or by the release time after a file write.
    static let weakCPUFraction = 0.02
    static let cpuWindow: TimeInterval = 5
    static let cpuWindowCount = 6
    static let hotWindowsNeeded = 3

    // A left-over command holds only while it uses the CPU. Every idle
    // helper measured stayed at or under 0.6 percent (Claude daemon and pty
    // host 0.6, Antigravity language server 0.4, Codex engines 0.2), and a
    // build or a test run uses many times more. An idle dev server was not
    // measured; 1 percent is the guess between the two.
    static let busyChildCPUFraction = 0.01

    /// A state file can be read in the middle of a write. The last state
    /// stays good for this long, then the state is unknown.
    static let reportMemory: TimeInterval = 10

    /// A hook working or idle older than this no longer beats the reported
    /// state. A hook wait has no such age: see `noteHookWait`.
    static let hookFreshness: TimeInterval = 60

    /// A write or a new working this much after the hook's wait is work
    /// that started again. The hook and the write of the tool call that
    /// asks can be a moment apart.
    static let hookWaitMargin: TimeInterval = 2

    /// Whether one child command counts as busy: its own subtree's CPU
    /// seconds over the collector's recent window.
    static func isBusyChild(cpuSeconds: Double, interval: TimeInterval) -> Bool {
        interval > 0 && cpuSeconds / interval >= busyChildCPUFraction
    }

    static func verdict(for evidence: AgentEvidence, memory: AgentMemory, settings: DetectionSettings, now: Date) -> (AgentVerdict, AgentMemory) {
        var memory = memory
        note(evidence, in: &memory, settings: settings, now: now)
        switch settings.rule(for: evidence.agentID) {
        case .ignore:
            return (AgentVerdict(state: .idle, confidence: .reported, reason: .ignoredByRule), memory)
        case .alwaysWorkingWhileOpen:
            return (AgentVerdict(state: .working, confidence: .reported, reason: .alwaysWorkingByRule), memory)
        case .automatic:
            break
        }
        if let state = statedState(of: evidence, memory: memory, settings: settings, now: now) {
            return (statedVerdict(state, evidence: evidence), memory)
        }
        return (inferredVerdict(evidence: evidence, memory: memory, settings: settings, now: now), memory)
    }

    /// The verdicts of one frame. An instance that is not in the frame is
    /// gone, and its memory goes with it.
    static func readings(for frame: EvidenceFrame, memory: [ProcessIdentity: AgentMemory], settings: DetectionSettings) -> ([AgentReading], [ProcessIdentity: AgentMemory]) {
        var kept: [ProcessIdentity: AgentMemory] = [:]
        var readings: [AgentReading] = []
        for evidence in frame.agents {
            let (verdict, next) = verdict(for: evidence, memory: memory[evidence.identity] ?? AgentMemory(), settings: settings, now: frame.at)
            kept[evidence.identity] = next
            readings.append(AgentReading(evidence: evidence, verdict: verdict, turn: turn(of: evidence, memory: next, settings: settings, now: frame.at)))
        }
        return (readings, kept)
    }

    /// The stated state before a left-over command or a background job
    /// makes it working again. `memory` is the one the verdict left.
    static func turn(of evidence: AgentEvidence, memory: AgentMemory, settings: DetectionSettings, now: Date) -> AgentTurn? {
        guard settings.rule(for: evidence.agentID) == .automatic,
              let state = statedState(of: evidence, memory: memory, settings: settings, now: now) else { return nil }
        let report = reportedState(memory: memory, settings: settings, now: now) == state ? memory.lastReport : nil
        guard state == .working else { return AgentTurn(state: state) }
        if report?.turnEnded == true { return AgentTurn(state: .idle) }
        // The time of a transcript is its last write, not the start of the turn.
        let startsTurn = report?.source == .claudeSessionFile || report?.source == .codexRollout
        return AgentTurn(state: .working, since: startsTurn ? report?.since : nil)
    }

    // MARK: Memory

    private static func note(_ evidence: AgentEvidence, in memory: inout AgentMemory, settings: DetectionSettings, now: Date) {
        memory.firstSeenAt = memory.firstSeenAt ?? now
        if evidence.busyChildCommands > 0 { memory.lastCommandAt = now }
        if evidence.backgroundJobsWorking > 0 { memory.lastBackgroundJobAt = now }
        if evidence.ownsSleepAssertion { memory.lastAssertionAt = now }
        if let write = fileWrite(of: evidence, now: now) {
            memory.lastFileWriteAt = max(memory.lastFileWriteAt ?? write, write)
        }
        if let report = stateReport(of: evidence) {
            memory.lastReport = report
            memory.lastReportSeenAt = now
        }
        noteHookWait(evidence, in: &memory, settings: settings, now: now)
        noteCPU(evidence, in: &memory, now: now)
        let statesWork = statedState(of: evidence, memory: memory, settings: settings, now: now) == .working
        noteWeakOnly(in: &memory, statesWork: statesWork, settings: settings, now: now)
    }

    /// A report from the file activity reader is a write, not a state. A
    /// write from before the process started belongs to an earlier run:
    /// opencode's database is shared by all its sessions.
    private static func fileWrite(of evidence: AgentEvidence, now: Date) -> Date? {
        let fromReport = evidence.reported.flatMap { $0.source == .fileActivity ? $0.observedAt : nil }
        guard let write = [evidence.fileActivityAt, fromReport].compactMap({ $0 }).max(),
              write >= Date(timeIntervalSince1970: evidence.startTime) else { return nil }
        return min(write, now)
    }

    private static func stateReport(of evidence: AgentEvidence) -> StateReport? {
        evidence.reported.flatMap { $0.source == .fileActivity ? nil : $0 }
    }

    /// A hook wait does not age out: nobody answers a permission question
    /// on a timer, and the rollout of a Codex that asks says "in a turn"
    /// all the time. The wait ends with the next hook event of its session
    /// and with the process. It also ends here, on a sign that the work
    /// started again without an event: a busy command, a working
    /// background job, or the agent's own working together with a session
    /// write or a state change after the wait began. An approved tool call
    /// sends its next event only when it is done.
    private static func noteHookWait(_ evidence: AgentEvidence, in memory: inout AgentMemory, settings: DetectionSettings, now: Date) {
        guard evidence.hookState == .waitingForUser, let at = evidence.hookStateAt, !isAhead(at, of: now) else {
            memory.endedHookWaitAt = nil
            return
        }
        guard memory.endedHookWaitAt != at else { return }
        var resumed = evidence.busyChildCommands > 0 || evidence.backgroundJobsWorking > 0
        if !resumed, reportedState(memory: memory, settings: settings, now: now) == .working {
            let after = at.addingTimeInterval(hookWaitMargin)
            let signs = [evidence.fileActivityAt, memory.lastReport?.since].compactMap { $0 }
            resumed = signs.contains { $0 > after }
        }
        memory.endedHookWaitAt = resumed ? at : nil
    }

    private static func noteCPU(_ evidence: AgentEvidence, in memory: inout AgentMemory, now: Date) {
        if evidence.sampleInterval > 0, evidence.subtreeCPUSeconds.isFinite {
            memory.cpuSamples.append(AgentMemory.CPUSample(at: now, cpuSeconds: evidence.subtreeCPUSeconds, interval: evidence.sampleInterval))
        }
        let span = cpuWindow * TimeInterval(cpuWindowCount)
        memory.cpuSamples.removeAll { now.timeIntervalSince($0.at) >= span || $0.at > now }
        if hasSteadyCPU(memory.cpuSamples, now: now) { memory.lastCPUAt = now }
    }

    /// The samples are sorted into windows by their age, and a window is hot
    /// when its samples together reach the threshold. So the rule reads the
    /// same at one sample per second and at one per five seconds.
    static func hasSteadyCPU(_ samples: [AgentMemory.CPUSample], now: Date) -> Bool {
        var cpu = [Double](repeating: 0, count: cpuWindowCount)
        var time = [TimeInterval](repeating: 0, count: cpuWindowCount)
        for sample in samples {
            let age = now.timeIntervalSince(sample.at)
            guard age >= 0, age < cpuWindow * TimeInterval(cpuWindowCount) else { continue }
            let index = Int(age / cpuWindow)
            cpu[index] += sample.cpuSeconds
            time[index] += sample.interval
        }
        let hot = zip(cpu, time).filter { $0.1 > 0 && $0.0 / $0.1 >= weakCPUFraction }.count
        return hot >= hotWindowsNeeded
    }

    /// Tracks how long CPU use has been the only thing that holds. A strong
    /// sign ends the count and lifts the cap, and so does the agent's own
    /// word that it works: CPU use is not the only sign then. Without a strong sign the count
    /// and the cap stay until the CPU rule has not held for as long as the
    /// cap itself: an agent that was quiet for that long and then starts
    /// again gets a new count, a process that spins all the time never is
    /// that quiet, and bursts with breaks a little longer than the release
    /// time do not start a new count each time.
    private static func noteWeakOnly(in memory: inout AgentMemory, statesWork: Bool, settings: DetectionSettings, now: Date) {
        if statesWork || isRecent(memory.lastStrongAt, within: settings.releaseAfterActivity, now: now) {
            memory.weakOnlySince = nil
            memory.weakCapped = false
        } else if isRecent(memory.lastCPUAt, within: settings.releaseAfterActivity, now: now) {
            let since = memory.weakOnlySince ?? now
            memory.weakOnlySince = since
            if now.timeIntervalSince(since) >= settings.weakEvidenceCap { memory.weakCapped = true }
        } else if !isRecent(memory.lastCPUAt, within: settings.weakEvidenceCap, now: now) {
            memory.weakOnlySince = nil
            memory.weakCapped = false
        }
    }

    private static func isRecent(_ date: Date?, within span: TimeInterval, now: Date) -> Bool {
        date.map { now.timeIntervalSince($0) < span } ?? false
    }

    // MARK: Stated

    /// The state the agent gives itself, nil when it gives none.
    private static func statedState(of evidence: AgentEvidence, memory: AgentMemory, settings: DetectionSettings, now: Date) -> WorkState? {
        if let hook = evidence.hookState, let at = evidence.hookStateAt, !isAhead(at, of: now) {
            if hook == .waitingForUser {
                if memory.endedHookWaitAt != at { return hook }
            } else if now.timeIntervalSince(at) <= hookFreshness {
                // One process can run many sessions, and the idle of one is
                // not the idle of all: the agent's own working stands.
                if hook == .idle, reportedState(memory: memory, settings: settings, now: now) == .working { return .working }
                return hook
            }
        }
        return reportedState(memory: memory, settings: settings, now: now)
    }

    /// A hook state from ahead of the clock was written before the clock
    /// was set back, and says nothing about now.
    private static func isAhead(_ at: Date, of now: Date) -> Bool {
        at.timeIntervalSince(now) > HookStateFile.clockTolerance
    }

    /// The state of the agent's own state file or session log.
    private static func reportedState(memory: AgentMemory, settings: DetectionSettings, now: Date) -> WorkState? {
        guard let report = memory.lastReport, let seen = memory.lastReportSeenAt,
              now.timeIntervalSince(seen) <= reportMemory else { return nil }
        if isLapsed(report, settings: settings, now: now) { return nil }
        return report.state
    }

    /// A working that was read from the last line of a transcript is a
    /// guess: an interrupt or a crash can leave that line for ever. It
    /// holds while the transcript was written within the release time, and
    /// after that the signs of activity decide. `since` is the last write.
    private static func isLapsed(_ report: StateReport, settings: DetectionSettings, now: Date) -> Bool {
        guard report.source == .claudeTranscript, report.state == .working else { return false }
        guard let lastWrite = report.since else { return true }
        return now.timeIntervalSince(lastWrite) >= settings.releaseAfterActivity
    }

    /// A working that the agent states itself never expires by age: a long
    /// tool call and a model wait are silent, and the instance ends when
    /// its process ends.
    private static func statedVerdict(_ state: WorkState, evidence: AgentEvidence) -> AgentVerdict {
        if state == .working {
            return AgentVerdict(state: .working, confidence: .reported, reason: .reportsBusy)
        }
        if evidence.busyChildCommands > 0 {
            return AgentVerdict(state: .working, confidence: .inferredStrong, reason: .runningCommand(evidence.busyChildCommands))
        }
        if evidence.backgroundJobsWorking > 0 {
            return AgentVerdict(state: .working, confidence: .inferredStrong, reason: .backgroundJob(evidence.backgroundJobsWorking))
        }
        if state == .waitingForUser {
            return AgentVerdict(state: .waitingForUser, confidence: .reported, reason: .asksPermission)
        }
        return AgentVerdict(state: .idle, confidence: .reported, reason: .atPrompt)
    }

    // MARK: Inferred

    /// For an agent with no state of its own: working while a strong sign is
    /// within the release time, or while CPU use holds under its cap.
    private static func inferredVerdict(evidence: AgentEvidence, memory: AgentMemory, settings: DetectionSettings, now: Date) -> AgentVerdict {
        let release = settings.releaseAfterActivity
        if let strong = memory.lastStrongAt, isRecent(strong, within: release, now: now) {
            return AgentVerdict(state: .working, confidence: .inferredStrong, reason: strongReason(evidence: evidence, memory: memory, lastAt: strong, now: now))
        }
        if isRecent(memory.lastCPUAt, within: release, now: now) {
            if memory.weakCapped {
                return AgentVerdict(state: .idle, confidence: .inferredWeak, reason: .onlyWeakSigns(minutes: Int(settings.weakEvidenceCap / 60)))
            }
            return AgentVerdict(state: .working, confidence: .inferredWeak, reason: .cpuActivity)
        }
        let quietSince = [memory.lastStrongAt, memory.lastCPUAt].compactMap { $0 }.max() ?? memory.firstSeenAt ?? now
        return AgentVerdict(state: .idle, confidence: .inferredWeak, reason: .noActivity(minutes: Int(now.timeIntervalSince(quietSince) / 60)))
    }

    private static func strongReason(evidence: AgentEvidence, memory: AgentMemory, lastAt: Date, now: Date) -> VerdictReason {
        if evidence.busyChildCommands > 0 { return .runningCommand(evidence.busyChildCommands) }
        if evidence.backgroundJobsWorking > 0 { return .backgroundJob(evidence.backgroundJobsWorking) }
        if evidence.ownsSleepAssertion { return .holdsSleepAssertion }
        let secondsAgo = Int(now.timeIntervalSince(lastAt))
        return memory.lastFileWriteAt == lastAt ? .writingSessionFile(secondsAgo: secondsAgo) : .workedRecently(secondsAgo: secondsAgo)
    }
}
