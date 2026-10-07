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
    /// Inferred, not said by the agent: see `CursorApprovalRule`.
    case awaitsApproval
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
        case .awaitsApproval: return "Waiting for your approval"
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
    /// The time of the hook working that stands now, as the hook wrote it.
    var hookWorkAt: Date?
    /// The same time, moved over the holes between samples (`SampleGap`),
    /// so `hookWorkingLimit` does not run out while the Mac sleeps.
    var hookWorkSince: Date?
    /// Since when every sign of `CursorApprovalRule` holds without a break.
    var approvalSignsSince: Date?
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

/// Cursor does not say that it waits for an approval: no transcript line
/// and no hook event exists for it. Its own code says what it does then
/// (docs/research/08-cursor.md): the main process holds a sleep assertion
/// from the prompt to the end of the answer, and gives it up while an
/// approval is pending. So a turn in progress with no assertion and no
/// command of the agent, for `settle` seconds, reads as a wait.
///
/// Measured on 2026-10-07 with Cursor 3.22.12: the assertion went 10
/// seconds after the last transcript write, and for the 12 minutes of the
/// wait the turn was open with no assertion, no command and no write.
///
/// It assumes that nothing else drops the assertion in the middle of a
/// turn for longer than `settle`. Set `enabled` to false when a recording
/// disproves that: Cursor then counts as working for the whole turn.
enum CursorApprovalRule {
    static let enabled = true
    /// The end of a turn looks the same for a while: Cursor was measured
    /// to write the end line 9 seconds after it gave up the assertion.
    /// The wait is said, and so told in a notification, only after this.
    static let settle: TimeInterval = 15

    /// The three inputs, as a recording holds them: `rep` (working, from
    /// the transcript), `pwr` (the assertion) and `cmds` (the commands).
    static func signs(of evidence: AgentEvidence) -> Bool {
        guard evidence.agentID == AgentCatalog.cursorDesktopID, let report = evidence.reported else { return false }
        if endedByStopHook(evidence) { return false }
        return signs(turnInProgress: report.source == .cursorTranscript && report.state == .working,
                     holdsAssertion: evidence.ownsSleepAssertion, childCommands: evidence.childCommands)
    }

    /// With the hooks on, Cursor's `stop` says that the turn is over, also
    /// when the transcript got no end line. Whether an aborted turn gets
    /// one is not measured, and without this an open last line read as
    /// working for as long as the file was listed. The stop counts while
    /// it is newer than the turn and than the last write to a transcript:
    /// a write after it is a turn that began with no event. The transcript
    /// lags behind (see `settle`), so a write that close after the stop
    /// still belongs to the turn that ended. An assertion or a command is
    /// the turn of another conversation.
    static func endedByStopHook(_ evidence: AgentEvidence) -> Bool {
        guard evidence.agentID == AgentCatalog.cursorDesktopID, evidence.hookState == .idle, let stop = evidence.hookStateAt,
              let report = evidence.reported, report.source == .cursorTranscript, report.state == .working,
              signs(turnInProgress: true, holdsAssertion: evidence.ownsSleepAssertion, childCommands: evidence.childCommands) else { return false }
        if let began = report.since, began > stop { return false }
        guard let write = evidence.fileActivityAt else { return true }
        return write.timeIntervalSince(stop) <= settle
    }

    static func signs(turnInProgress: Bool, holdsAssertion: Bool, childCommands: Int) -> Bool {
        turnInProgress && !holdsAssertion && childCommands == 0
    }

    static func waits(signsSince: Date?, now: Date, enabled: Bool = CursorApprovalRule.enabled, settle: TimeInterval = CursorApprovalRule.settle) -> Bool {
        guard enabled, let signsSince else { return false }
        return now.timeIntervalSince(signsSince) >= settle
    }
}

/// Turns evidence into a state. Pure: the caller keeps the memory and
/// passes the time.
///
/// The sources, most trusted first:
/// 1. a fresh hook state, a hook wait of any age that has not ended, or
///    the hook working of an agent with no state of its own,
/// 2. the reported state (state file or session log),
/// 3. strong signs: a busy command, a working background job, a sleep
///    assertion of the agent's own, a session-file write,
/// 4. weak signs: CPU use.
/// A hook idle does not beat a reported working, but for Cursor's `stop`:
/// see `CursorApprovalRule.endedByStopHook`.
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

    /// An agent with no state of its own (Droid, opencode) says through
    /// its hooks alone that it works, and a tool call sends no event while
    /// it runs. So its hook working stands until the next event of the
    /// session or the end of the process. A Stop that never arrives must
    /// not hold the Mac for ever: after this long without an event the
    /// signs of activity decide again, as for an agent with no hooks. As
    /// long as `DetectionSettings.weakEvidenceCap`, the other limit on a
    /// working that nothing ends.
    static let hookWorkingLimit: TimeInterval = 1800

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
        if CursorApprovalRule.waits(signsSince: memory.approvalSignsSince, now: now) {
            return (AgentVerdict(state: .waitingForUser, confidence: .inferredStrong, reason: .awaitsApproval), memory)
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
        guard settings.rule(for: evidence.agentID) == .automatic else { return nil }
        if CursorApprovalRule.waits(signsSince: memory.approvalSignsSince, now: now) { return AgentTurn(state: .waitingForUser) }
        guard let stated = statedState(of: evidence, memory: memory, settings: settings, now: now) else {
            // An agent that speaks through its hooks only: the idle of a
            // hook stands for the turn until the next event, at any age,
            // so a command that runs on is no new work. Its working
            // stands too, also after `hookWorkingLimit`: the turn ends
            // with its Stop, and is told once.
            guard let hook = evidence.hookState, let at = evidence.hookStateAt, !isAhead(at, of: now) else { return nil }
            if hook == .idle { return AgentTurn(state: .idle) }
            if hook == .working, standsOnHooks(evidence) { return AgentTurn(state: .working) }
            return nil
        }
        var state = stated
        var report = reportedState(memory: memory, settings: settings, now: now) == state ? memory.lastReport : nil
        // A fresh hook state beats the agent's own in the verdict. For the
        // turn the newer of the two counts: Claude Code was recorded with
        // "waiting" in its session file 6 seconds before the hook said
        // so, and an interrupt ends a turn with no hook event at all.
        if report == nil, let own = memory.lastReport, let reported = reportedState(memory: memory, settings: settings, now: now),
           let since = own.since, let hookAt = evidence.hookStateAt, since > hookAt, since <= now {
            state = reported
            report = own
        }
        guard state == .working else { return AgentTurn(state: state) }
        if report?.turnEnded == true { return AgentTurn(state: .idle) }
        // The time of a transcript is its last write, not the start of the turn.
        let startsTurn = report?.source == .claudeSessionFile || report?.source == .codexRollout || report?.source == .cursorTranscript
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
        noteHookWork(evidence, in: &memory, now: now)
        let signsSince = memory.approvalSignsSince.flatMap { $0 <= now ? $0 : nil }
        memory.approvalSignsSince = CursorApprovalRule.signs(of: evidence) ? signsSince ?? now : nil
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

    /// Keeps the time of the hook working that stands. A new event has a
    /// new time and starts the count again.
    private static func noteHookWork(_ evidence: AgentEvidence, in memory: inout AgentMemory, now: Date) {
        guard evidence.hookState == .working, let at = evidence.hookStateAt, !isAhead(at, of: now) else {
            memory.hookWorkAt = nil
            memory.hookWorkSince = nil
            return
        }
        guard memory.hookWorkAt != at else { return }
        memory.hookWorkAt = at
        memory.hookWorkSince = min(at, now)
    }

    /// Whether the hooks are all this agent says about itself. An agent
    /// with a session file, a rollout or a transcript is judged by that
    /// once its hook state is no longer fresh.
    private static func standsOnHooks(_ evidence: AgentEvidence) -> Bool {
        evidence.level != .state
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
            } else if CursorApprovalRule.endedByStopHook(evidence) {
                return .idle
            } else if now.timeIntervalSince(at) <= hookFreshness {
                // One process can run many sessions, and the idle of one is
                // not the idle of all: the agent's own working stands.
                if hook == .idle, reportedState(memory: memory, settings: settings, now: now) == .working { return .working }
                return hook
            } else if hook == .working, standsOnHooks(evidence), let since = memory.hookWorkSince, now.timeIntervalSince(since) < hookWorkingLimit {
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
