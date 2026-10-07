import Darwin
import Foundation

/// One sample: the frame, and what to watch so the next sample can come
/// sooner than the timer.
struct EvidenceSample: Equatable {
    var frame: EvidenceFrame
    /// The state and session files of the instances in the frame.
    var watchedFiles: Set<String> = []
    /// The root process of each instance in the frame.
    var roots: Set<ProcessIdentity> = []
    /// Seconds the sample took to collect.
    var cost: TimeInterval = 0
    /// For the menu only, beside the frame and never in it: a session name
    /// must not reach a recording or a log.
    var sessionHints: [ProcessIdentity: SessionHint] = [:]
}

protocol EvidenceCollecting: AnyObject {
    func collect(userNames: [String]) -> EvidenceSample
}

/// What `stat` says about a file. A file with the same signature as at the
/// last sample is not read again.
struct FileSignature: Equatable {
    var modifiedAt: Date
    var size: UInt64
    var inode: UInt64

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        modifiedAt = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        size = UInt64(max(info.st_size, 0))
        inode = UInt64(info.st_ino)
    }
}

/// Parsed files by path. An entry that no sample asked for is dropped.
struct FileCache<Value> {
    private var entries: [String: (signature: FileSignature, value: Value?)] = [:]
    private var used: Set<String> = []

    /// Nil when the file is missing. The value is nil when the file is there
    /// and was not understood, as in the middle of a write.
    mutating func value(at path: String, read: () -> Value?) -> (value: Value?, signature: FileSignature)? {
        guard let signature = FileSignature(path: path) else {
            entries[path] = nil
            return nil
        }
        used.insert(path)
        if let entry = entries[path], entry.signature == signature { return (entry.value, signature) }
        let value = read()
        entries[path] = (signature, value)
        return (value, signature)
    }

    mutating func endSample() {
        if entries.count != used.count { entries = entries.filter { used.contains($0.key) } }
        used.removeAll(keepingCapacity: true)
    }
}

/// Fills one `EvidenceFrame` per call. This is the impure layer: it reads
/// the process table, the agents' own files and the power state, and it
/// keeps what a delta needs from the previous sample. It makes no
/// judgement. Not thread safe: call it from one queue.
///
/// Measured on the test Mac with about 660 processes and 13 instances, on
/// the `.utility` queue: a sample costs 3 ms in a release build and 5 ms in
/// a debug build. The process table is about 2 ms of that, because it reads
/// the usage of every process of the user. The first sample also reads
/// every argv and matches it, and costs 25 to 45 ms.
final class EvidenceCollector: EvidenceCollecting {
    struct Sources {
        var census: ProcessCensusing
        var assertions: PowerAssertionListing
        var power: PowerContextReading
        var openFiles: OpenFileListing
        var catalog = AgentCatalog.standard
        var claudeSessions = ClaudeSessionStateReader()
        var claudeJobs = ClaudeJobStateReader()
        /// `~/.claude/projects`, for the transcript of a Claude Code that
        /// writes no session file.
        var claudeProjects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        var codexRollouts = CodexRolloutReader()
        var cursorTranscripts = CursorTranscriptReader()
        /// Bytes of a rollout that one sample searches for a turn marker.
        var rolloutSearchBudget = CodexRolloutTracker.defaultSearchBudget
        /// Session stores of the agents that are judged by activity, by
        /// `AgentDefinition.id`.
        var fileActivityTargets: [String: FileActivityReader.Target] = [
            "opencode": FileActivityReader.opencode,
            "antigravity-desktop": FileActivityReader.antigravity,
            "antigravity": FileActivityReader.antigravity,
        ]
        /// The folder the hook command writes into. Nil reads no hook state.
        var hookDirectory: URL?
        /// `~/.claude/settings.json`, for the Remote Control switch. Nil reads none.
        var claudeSettings: URL?
        var now: () -> Date = Date.init
        /// Seconds the Mac was awake since boot. Nil records none, and a
        /// hole between two samples is then judged by the date alone.
        var awakeSeconds: (() -> TimeInterval)?

        static func system() -> Sources {
            var sources = Sources(census: SystemProcessCensus(), assertions: SystemPowerAssertions(), power: SystemPowerContext(), openFiles: SystemOpenFiles())
            sources.hookDirectory = HookStateFile.directory()
            sources.claudeSettings = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
            sources.awakeSeconds = SampleGap.awakeSeconds
            return sources
        }
    }

    /// A child command is busy when it used the CPU in both halves of this
    /// many seconds. One burst is no running command: Codex desktop starts
    /// five `node` helpers when a thread loads, and on the test Mac their
    /// start-up read as a command of an idle engine.
    static let childWindow: TimeInterval = 10
    /// A desktop app has a live session for this long after its last write.
    static let liveSessionAge: TimeInterval = 3600
    /// How often a Claude project directory and the Cursor transcripts
    /// are listed again to find a new file.
    static let listingAge: TimeInterval = 5
    /// How often the dated folders of the Codex sessions are listed, for a
    /// session that holds no rollout open. The whole tree took 151 ms to
    /// list at 10,000 rollouts, every 5 seconds.
    static let rolloutListingAge: TimeInterval = 60
    /// The dated folders that are listed: today's and yesterday's.
    static let rolloutListingDays = 2
    static let codexIDs: Set<String> = ["codex", "codex-desktop"]
    /// For how long after the last good read the previous frame is kept
    /// while the process table cannot be read. A time and not a count of
    /// samples: an event brings a sample 0.2 seconds after the one before.
    static let heldSeconds: TimeInterval = 30

    /// One more way to say that phone access is on, next to what
    /// `RemoteAccessDetector` finds. Nothing detects SSH or screen sharing yet.
    var remoteAccessProbe: () -> Bool = { false }

    private var sources: Sources

    private struct MatchEntry {
        var startTime: TimeInterval
        var executablePath: String
        var arguments: [String]
        var match: AgentMatch?
    }

    private struct CPUSample {
        var at: Date
        var cpuSeconds: Double
        var interval: TimeInterval
    }

    private var matchCache: [Int32: MatchEntry] = [:]
    private var matchUserNames: [String] = []
    private var previous: SampleTime?
    private var lastSample: EvidenceSample?
    private var lastReadableAt: SampleTime?
    private var previousRows: [ProcessIdentity: ProcessInfoRow] = [:]
    private var childWindows: [ProcessIdentity: [CPUSample]] = [:]
    private var sessionFiles = FileCache<ClaudeSessionState>()
    private var jobFiles = FileCache<ClaudeJobState>()
    private var transcripts = FileCache<ClaudeTranscriptReader.TailParse>()
    private var rolloutTails: CodexRolloutTracker
    private var rolloutCwds: [String: String] = [:]
    private var rolloutListing: (at: Date, files: [CodexRolloutFile])?
    /// The rollouts of each Codex session of the sample that is being collected.
    private var sessionRollouts: [ProcessIdentity: [String]] = [:]
    private var cursorTails = CursorTranscriptTracker()
    private var cursorListing: (at: Date, files: [CursorTranscriptFile])?
    /// When the turn of each Cursor conversation ended, by the key of its
    /// hook session, for the sample that is being collected.
    private var cursorEnds: [String: Date] = [:]
    /// The hook states of the sample that is being collected, by pid.
    private var sampleHookStates: [Int32: HookStateReader.State] = [:]
    private var transcriptChoices: [ProcessIdentity: (at: Date, path: String?)] = [:]
    private var activityReaders: [String: FileActivityReader] = [:]
    private var hookReader: HookStateReader?
    /// The session names of the sample that is being collected.
    private var sessionNames: [ProcessIdentity: String] = [:]
    private var claudeSettingsFiles = FileCache<RemoteAccessDetector.ClaudeSettings>()

    init(sources: Sources = .system()) {
        self.sources = sources
        rolloutTails = CodexRolloutTracker(searchBudget: sources.rolloutSearchBudget)
        hookReader = sources.hookDirectory.map(HookStateReader.init(directory:))
        hookReader?.prepare()
    }

    func collect(userNames: [String] = []) -> EvidenceSample {
        let started = DispatchTime.now().uptimeNanoseconds
        let time = SampleTime(at: sources.now(), awake: sources.awakeSeconds?())
        let now = time.at
        guard let snapshot = sources.census.snapshot() ?? unreadableTable(time: time, started: started) else {
            return lastSample ?? EvidenceSample(frame: EvidenceFrame(at: now, agents: []))
        }
        let matches = currentMatches(in: snapshot, userNames: userNames)
        let instances = sources.catalog.instances(in: snapshot, matches: matches)
        let asserting = instances.isEmpty ? [] : sources.assertions.assertingPIDs()
        // The CPU a process used before and after a sleep, over an interval
        // that is mostly the sleep, would read as no use at all.
        // A clock that was set is a hole too: no interval can be trusted.
        let gap = SampleGap.length(from: previous, to: time) != nil
        let interval = gap ? 0 : previous.map { SampleGap.interval(from: $0, to: time) } ?? 0
        if gap { childWindows.removeAll() }

        var sample = EvidenceSample(frame: EvidenceFrame(at: now, agents: [], context: context(snapshot: snapshot, matches: matches)))
        sample.frame.awake = time.awake
        let hookStates = hookReader?.states(snapshot: snapshot, now: now) ?? [:]
        sampleHookStates = hookStates
        // A new state file is a new entry in the folder.
        if let hookReader { sample.watchedFiles.insert(hookReader.directory.path) }
        sessionRollouts = codexSessionRollouts(of: instances, matches: matches, now: now)
        var activities: [String: FileActivity] = [:]
        var rows: [ProcessIdentity: ProcessInfoRow] = [:]
        var liveUnits: Set<ProcessIdentity> = []
        for instance in instances {
            for row in instance.rows { rows[row.identity] = row }
            guard var evidence = agentEvidence(for: instance, matches: matches, now: now, activities: &activities, watched: &sample.watchedFiles) else { continue }
            noteUse(of: instance, matches: matches, interval: interval, now: now, in: &evidence, liveUnits: &liveUnits)
            if instance.definition.id == AgentCatalog.cursorDesktopID {
                // Cursor's own wake lock is held by the main process. A
                // `caffeinate` in a terminal of the editor is not the agent's.
                evidence.ownsSleepAssertion = asserting.contains(instance.rootPID)
            } else {
                evidence.ownsSleepAssertion = instance.rows.contains { asserting.contains($0.pid) }
            }
            noteHooks(of: instance, matches: matches, states: hookStates, now: now, in: &evidence, watched: &sample.watchedFiles)
            sample.frame.agents.append(evidence)
            sample.roots.insert(instance.identity)
            let hint = SessionHint(
                name: sessionNames[instance.identity],
                terminal: instance.rows.first.flatMap { SessionHint.terminalName(device: $0.tty) }
            )
            if !hint.isEmpty { sample.sessionHints[instance.identity] = hint }
        }
        sessionNames.removeAll(keepingCapacity: true)
        cursorEnds.removeAll(keepingCapacity: true)
        sampleHookStates.removeAll(keepingCapacity: true)

        previous = time
        previousRows = rows
        childWindows = childWindows.filter { liveUnits.contains($0.key) }
        activityReaders = activityReaders.filter { activities[$0.key] != nil }
        transcriptChoices = transcriptChoices.filter { sample.roots.contains($0.key) }
        sessionFiles.endSample()
        jobFiles.endSample()
        transcripts.endSample()
        rolloutTails.endSample()
        cursorTails.endSample()
        claudeSettingsFiles.endSample()
        sample.cost = TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        lastSample = sample
        lastReadableAt = time
        return sample
    }

    /// The process table could not be read. That says nothing about the
    /// agents, so the previous frame stands for this sample, with the new
    /// time, the power state of now and no CPU numbers. Nil means: go on
    /// with what was kept in `lastSample`. `heldSeconds` after the last
    /// good read the table counts as empty, and the empty table is
    /// returned.
    private func unreadableTable(time: SampleTime, started: UInt64) -> [ProcessInfoRow]? {
        let held = lastReadableAt.map { SampleGap.interval(from: $0, to: time) }
        guard let held, held >= 0, held <= Self.heldSeconds, var sample = lastSample else {
            lastSample = nil
            return []
        }
        sample.frame.at = time.at
        sample.frame.awake = time.awake
        // The battery and the heat do not wait for the table. Phone access
        // is read from the table, so it stays as it was.
        var context = sources.power.context()
        context.remoteAccessDetected = sample.frame.context.remoteAccessDetected
        sample.frame.context = context
        for index in sample.frame.agents.indices {
            sample.frame.agents[index].sampleInterval = 0
            sample.frame.agents[index].subtreeCPUSeconds = 0
            sample.frame.agents[index].energyNanojoules = nil
            sample.frame.agents[index].logicalWriteBytes = nil
        }
        sample.cost = TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        lastSample = sample
        return nil
    }

    private func context(snapshot: [ProcessInfoRow], matches: [Int32: AgentMatch]) -> FrameContext {
        var context = sources.power.context()
        context.remoteAccessDetected = remoteAccessProbe() || claudeRemoteControl(snapshot: snapshot, matches: matches)
        return context
    }

    private func claudeRemoteControl(snapshot: [ProcessInfoRow], matches: [Int32: AgentMatch]) -> Bool {
        let sessions = snapshot.filter { matches[$0.pid].map { $0.definition.id == "claude" && $0.role == .session } ?? false }
        guard !sessions.isEmpty else { return false }
        var settings = RemoteAccessDetector.ClaudeSettings()
        if let url = sources.claudeSettings,
           let hit = claudeSettingsFiles.value(at: url.path, read: { (try? Data(contentsOf: url)).map(RemoteAccessDetector.ClaudeSettings.init(json:)) }),
           let read = hit.value {
            settings = read
        }
        let claudeSessions = sessions.map { RemoteAccessDetector.ClaudeSession(arguments: AgentCatalog.command(of: $0).arguments, hasTerminal: $0.hasTTY) }
        return RemoteAccessDetector.claudeRemoteControl(sessions: claudeSessions, settings: settings)
    }

    /// The state the agent's hooks left for one of the instance's own
    /// processes. A launcher and the binary it starts are one instance, and
    /// the hook runs below either.
    ///
    /// Cursor's hook session is a conversation, and a conversation is a
    /// transcript: `conversation_id` is the name of the transcript's
    /// folder (docs/research/08-cursor.md). So each hook session is set
    /// against the end of its own transcript.
    private func noteHooks(
        of instance: AgentInstance, matches: [Int32: AgentMatch], states: [Int32: HookStateReader.State], now: Date,
        in evidence: inout AgentEvidence, watched: inout Set<String>
    ) {
        guard !states.isEmpty, let hookAgent = HookEvents.hookAgent(forDefinition: instance.definition.id) else { return }
        let bySession = instance.definition.id == AgentCatalog.cursorDesktopID
        let own = instance.rows.compactMap { row -> HookStateReader.State? in
            guard var state = states[row.pid], state.agent == hookAgent,
                  let match = matches[row.pid], match.definition.id == instance.definition.id, match.role != .helper else { return nil }
            if bySession, let summary = state.file.summary(
                now: now, freshness: VerdictRules.hookFreshness, workingLimit: VerdictRules.hookWorkingLimit, ended: cursorEnds
            ) {
                state.state = summary.state
                state.at = summary.at
            }
            return state
        }
        own.forEach { watched.insert($0.path) }
        guard let newest = own.max(by: { $0.at < $1.at }) else { return }
        evidence.hookState = newest.state
        evidence.hookStateAt = newest.at
        evidence.hookStateBySession = bySession
    }

    // MARK: Matching

    /// Matching reads the path and argv of each process against the whole
    /// catalog, and both stay the same for the life of a process, so the
    /// answer is kept. An exec keeps the pid and changes the path or argv.
    private func currentMatches(in snapshot: [ProcessInfoRow], userNames: [String]) -> [Int32: AgentMatch] {
        if userNames != matchUserNames {
            matchUserNames = userNames
            matchCache.removeAll(keepingCapacity: true)
        }
        var alive: [Int32: MatchEntry] = [:]
        alive.reserveCapacity(snapshot.count)
        var matches: [Int32: AgentMatch] = [:]
        for row in snapshot {
            var entry: MatchEntry
            if let known = matchCache[row.pid], known.startTime == row.startTime,
               known.executablePath == row.executablePath, known.arguments == row.arguments {
                entry = known
            } else {
                entry = MatchEntry(startTime: row.startTime, executablePath: row.executablePath, arguments: row.arguments,
                                   match: sources.catalog.match(row, userNames: userNames))
            }
            alive[row.pid] = entry
            if let match = entry.match { matches[row.pid] = match }
        }
        matchCache = alive
        return matches
    }

    // MARK: Per agent

    /// Nil for an instance that is no agent after all: a warm Claude spare.
    private func agentEvidence(
        for instance: AgentInstance, matches: [Int32: AgentMatch], now: Date,
        activities: inout [String: FileActivity], watched: inout Set<String>
    ) -> AgentEvidence? {
        let definition = instance.definition
        var evidence = AgentEvidence(
            agentID: definition.id, displayName: definition.displayName, level: definition.level, kind: definition.kind,
            role: instance.role == .helperMaybeSession ? .session : instance.role,
            pid: instance.rootPID, startTime: instance.rootStartTime
        )
        if definition.id == "claude" {
            guard fillClaude(&evidence, instance: instance, matches: matches, now: now, watched: &watched) else { return nil }
        } else if Self.codexIDs.contains(definition.id) {
            fillCodex(&evidence, instance: instance, matches: matches, now: now, watched: &watched)
        } else if definition.id == AgentCatalog.cursorDesktopID {
            fillCursor(&evidence, instance: instance, now: now, watched: &watched)
        } else if let target = sources.fileActivityTargets[definition.id] {
            let activity = activities[definition.id] ?? pollActivity(definition.id, target: target)
            activities[definition.id] = activity
            evidence.reported = FileActivityReader.report(for: activity, now: now)
            evidence.fileActivityAt = activity.newestModification
            evidence.hasLiveSession = definition.kind == .desktop && isRecent(activity.newestModification, now: now)
        }
        return evidence
    }

    private func pollActivity(_ id: String, target: FileActivityReader.Target) -> FileActivity {
        var reader = activityReaders[id] ?? FileActivityReader(target: target)
        defer { activityReaders[id] = reader }
        return reader.poll()
    }

    private func isRecent(_ date: Date?, now: Date) -> Bool {
        date.map { now.timeIntervalSince($0) <= Self.liveSessionAge } ?? false
    }

    // MARK: Claude Code

    /// False when the instance is to be left out of the frame.
    private func fillClaude(_ evidence: inout AgentEvidence, instance: AgentInstance, matches: [Int32: AgentMatch], now: Date, watched: inout Set<String>) -> Bool {
        // A launcher and the binary it starts are one instance, and the
        // session file is under the pid of the one that runs the session.
        let own = instance.rows.filter { matches[$0.pid].map { $0.definition.id == "claude" && $0.role != .helper } ?? false }
        var found: (state: ClaudeSessionState?, path: String)?
        for row in own {
            let path = sources.claudeSessions.fileURL(forPid: row.pid).path
            let reader = sources.claudeSessions
            guard let hit = sessionFiles.value(at: path, read: { reader.state(forPid: row.pid, now: now) }) else { continue }
            found = (hit.value, path)
            break
        }
        guard let found else {
            // A spare with no session file has no job yet.
            guard instance.role != .helperMaybeSession else { return false }
            fillFromTranscript(&evidence, instance: instance, now: now, watched: &watched)
            return true
        }
        watched.insert(found.path)
        // A file that is there and cannot be read keeps the instance: the
        // verdict remembers the last state for a short time.
        guard var state = found.state else { return true }
        if instance.role == .helperMaybeSession, state.kind == .spare, state.state == .idle { return false }
        state.observedAt = now
        evidence.reported = state.report
        sessionNames[instance.identity] = state.name
        if let jobID = state.jobID {
            let reader = sources.claudeJobs
            let path = reader.jobsDirectory.appendingPathComponent(jobID).appendingPathComponent("state.json").path
            if let job = jobFiles.value(at: path, read: { reader.state(forJobID: jobID, now: now) }) {
                watched.insert(path)
                if job.value?.state == .working { evidence.backgroundJobsWorking = 1 }
            }
        }
        return true
    }

    /// Claude Code before 2.1.119: the newest transcript of the process's
    /// working directory that was written since the process started.
    private func fillFromTranscript(_ evidence: inout AgentEvidence, instance: AgentInstance, now: Date, watched: inout Set<String>) {
        var choice = transcriptChoices[instance.identity]
        if choice.map({ now.timeIntervalSince($0.at) >= Self.listingAge || $0.at > now }) ?? true {
            choice = (now, newestTranscript(for: instance))
            transcriptChoices[instance.identity] = choice
        }
        guard let path = choice?.path else { return }
        let url = URL(fileURLWithPath: path)
        guard let hit = transcripts.value(at: path, read: { ClaudeTranscriptReader.parseTail(of: url) }), let parsed = hit.value else { return }
        watched.insert(path)
        evidence.fileActivityAt = hit.signature.modifiedAt
        evidence.reported = ClaudeTranscriptReader.report(from: parsed, lastWrite: hit.signature.modifiedAt, now: now)
    }

    private func newestTranscript(for instance: AgentInstance) -> String? {
        guard let cwd = sources.openFiles.workingDirectory(of: instance.rootPID) else { return nil }
        let directory = sources.claudeProjects.appendingPathComponent(Self.claudeProjectName(forDirectory: cwd))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let started = Date(timeIntervalSince1970: instance.rootStartTime)
        var newest: (path: String, at: Date)?
        for name in names where name.hasSuffix(".jsonl") {
            let path = directory.appendingPathComponent(name).path
            guard let signature = FileSignature(path: path), signature.modifiedAt >= started else { continue }
            if newest.map({ signature.modifiedAt > $0.at }) ?? true { newest = (path, signature.modifiedAt) }
        }
        return newest?.path
    }

    /// Claude Code names a project directory after the working directory,
    /// with every character that is no letter or digit replaced by `-`.
    static func claudeProjectName(forDirectory path: String) -> String {
        String(path.unicodeScalars.map { scalar -> Character in
            let keep = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))
            return keep ? Character(scalar) : "-"
        })
    }

    // MARK: Codex

    private func fillCodex(_ evidence: inout AgentEvidence, instance: AgentInstance, matches: [Int32: AgentMatch], now: Date, watched: inout Set<String>) {
        let started = Date(timeIntervalSince1970: instance.rootStartTime)
        let paths: [String]
        if instance.role == .engine {
            // A shared engine keeps the rollout of every loaded thread open.
            // An engine can run below another one and is the same instance.
            var open: Set<String> = []
            var readable = false
            for row in instance.rows where matches[row.pid]?.role == .engine {
                guard let files = sources.openFiles.openFilePaths(of: row.pid) else { continue }
                readable = true
                open.formUnion(files.filter(Self.isRolloutPath))
            }
            guard readable else { return }
            paths = open.sorted()
        } else {
            paths = sessionRollouts[instance.identity] ?? []
        }

        var working = false
        var workingSince: Date?
        var newestMarker: Date?
        var newestWrite: Date?
        var sawMarker = false
        var unknown = false
        for path in paths {
            guard let hit = rolloutTails.read(path: path) else { continue }
            watched.insert(path)
            newestWrite = max(newestWrite ?? hit.signature.modifiedAt, hit.signature.modifiedAt)
            // The newest marker of this file is not found yet, so the file
            // may hold a turn in progress.
            guard hit.resolved else {
                unknown = true
                continue
            }
            let turn = hit.turn
            guard turn.lastMarker != nil else { continue }
            sawMarker = true
            if let at = turn.markerAt { newestMarker = max(newestMarker ?? at, at) }
            // A killed Codex leaves a turn that never ends. Only a file that
            // this process wrote can hold a turn of this process.
            if turn.turnInProgress, hit.signature.modifiedAt >= started, !working {
                working = true
                workingSince = turn.markerAt
            }
        }
        evidence.fileActivityAt = newestWrite
        if working {
            evidence.reported = StateReport(state: .working, since: workingSince, observedAt: now, source: .codexRollout, detail: "in a turn")
        } else if unknown {
            // No state: idle is said only when every file was read to a marker.
        } else if sawMarker || instance.role == .engine {
            // An engine with no thread in a turn is idle, also with no thread loaded.
            evidence.reported = StateReport(state: .idle, since: newestMarker, observedAt: now, source: .codexRollout, detail: nil)
        }
        if instance.definition.kind == .desktop {
            evidence.hasLiveSession = working || isRecent(newestWrite, now: now)
        }
    }

    static func isRolloutPath(_ path: String) -> Bool {
        guard path.hasSuffix(".jsonl"), let slash = path.lastIndex(of: "/") else { return false }
        return path[path.index(after: slash)...].hasPrefix("rollout-")
    }

    /// `codex exec` and the TUI. Rollouts carry no pid, so a rollout is
    /// tied to a session by the file the process holds open, as for the
    /// engines. Two sessions in one folder each read their own file then:
    /// the end of one turn is not the end of the other, and a turn that a
    /// killed session left open is not the turn of the one that lives.
    ///
    /// A session that holds no rollout open gets the newest rollout of its
    /// working directory that was written since it started, and only when
    /// no other such session runs in that directory: with two of them
    /// nobody can say which file is whose. No file goes to two sessions.
    private func codexSessionRollouts(of instances: [AgentInstance], matches: [Int32: AgentMatch], now: Date) -> [ProcessIdentity: [String]] {
        let sessions = instances.filter { Self.codexIDs.contains($0.definition.id) && $0.role != .engine }
        guard !sessions.isEmpty else { return [:] }
        var found: [ProcessIdentity: [String]] = [:]
        var taken: Set<String> = []
        var searching: [(instance: AgentInstance, cwd: String)] = []
        for instance in sessions {
            var open: Set<String> = []
            for row in instance.rows where matches[row.pid].map({ $0.definition.id == instance.definition.id && $0.role == .session }) ?? false {
                open.formUnion((sources.openFiles.openFilePaths(of: row.pid) ?? []).filter(Self.isRolloutPath).map(Self.resolved))
            }
            open.subtract(taken)
            if !open.isEmpty {
                found[instance.identity] = open.sorted()
                taken.formUnion(open)
            } else if let cwd = sources.openFiles.workingDirectory(of: instance.rootPID).map(Self.resolved) {
                searching.append((instance, cwd))
            }
        }
        guard !searching.isEmpty else { return found }
        if rolloutListing.map({ now.timeIntervalSince($0.at) >= Self.rolloutListingAge || $0.at > now }) ?? true {
            rolloutListing = (now, sources.codexRollouts.filesOfLastDays(Self.rolloutListingDays, now: now))
            let listed = Set(rolloutListing?.files.map(\.url.path) ?? [])
            rolloutCwds = rolloutCwds.filter { listed.contains($0.key) }
        }
        let files = rolloutListing?.files ?? []
        let sharing = Dictionary(searching.map { ($0.cwd, 1) }, uniquingKeysWith: +)
        for (instance, cwd) in searching where sharing[cwd] == 1 {
            let started = Date(timeIntervalSince1970: instance.rootStartTime)
            // Newest first, as the listing is.
            for file in files where file.lastWrite >= started {
                let path = file.url.path
                guard !taken.contains(Self.resolved(path)) else { continue }
                let fileCwd = rolloutCwds[path] ?? CodexRolloutReader.sessionCwd(of: file.url).map(Self.resolved)
                guard let fileCwd else { continue }
                rolloutCwds[path] = fileCwd
                guard fileCwd == cwd else { continue }
                found[instance.identity] = [path]
                taken.insert(Self.resolved(path))
                break
            }
        }
        return found
    }

    /// `/tmp` and `/private/tmp` are the same directory.
    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: Cursor

    /// One evidence for the app, as for the Codex app: the transcripts
    /// carry no pid and no window, so every conversation of this Mac's
    /// Cursor counts for the one running Cursor.
    private func fillCursor(_ evidence: inout AgentEvidence, instance: AgentInstance, now: Date, watched: inout Set<String>) {
        if cursorListing.map({ now.timeIntervalSince($0.at) >= Self.listingAge || $0.at > now }) ?? true {
            cursorListing = (now, sources.cursorTranscripts.recentFiles(now: now))
        }
        let started = Date(timeIntervalSince1970: instance.rootStartTime)
        var readings: [(file: CursorTranscriptFile, reading: CursorTranscriptTracker.Reading)] = []
        for file in cursorListing?.files ?? [] where file.lastWrite >= started {
            guard let reading = cursorTails.read(path: file.url.path) else { continue }
            watched.insert(file.url.path)
            readings.append((file, reading))
        }
        // The stop of a conversation ends the open turn of that
        // conversation only, so it is set against its own transcript here.
        let hookAgent = HookEvents.hookAgent(forDefinition: instance.definition.id)
        let stops = instance.rows.compactMap { sampleHookStates[$0.pid] }.filter { $0.agent == hookAgent }
            .reduce(into: [String: Date]()) { stops, state in stops.merge(state.file.stops(now: now), uniquingKeysWith: max) }
        let summary = CursorSummary.make(of: readings, engineStarted: started, stops: stops)
        evidence.reported = summary.report(now: now)
        cursorEnds = Dictionary(summary.ends.map { (HookStateFile.sessionKey($0.key), $0.value) }, uniquingKeysWith: max)
        evidence.fileActivityAt = summary.newestWrite
        evidence.hasLiveSession = summary.working || isRecent(summary.newestWrite, now: now)
        sessionNames[instance.identity] = summary.projectSlug.flatMap(CursorTranscriptReader.label(forSlug:))
    }

    // MARK: Process use

    private static func isBusy(_ samples: [CPUSample]) -> Bool {
        VerdictRules.isBusyChild(cpuSeconds: samples.reduce(0) { $0 + $1.cpuSeconds }, interval: samples.reduce(0) { $0 + $1.interval })
    }

    /// The subtree's use since the previous sample, and the child commands.
    /// A child command is a top process below the agent that is no agent,
    /// engine or helper itself, together with what it started.
    private func noteUse(
        of instance: AgentInstance, matches: [Int32: AgentMatch], interval: TimeInterval, now: Date,
        in evidence: inout AgentEvidence, liveUnits: inout Set<ProcessIdentity>
    ) {
        // The verdict wants no CPU number on the first sample of a process:
        // all it used since it started would count as one burst.
        let known = interval > 0 && previousRows[instance.identity] != nil
        let cursor = instance.definition.id == AgentCatalog.cursorDesktopID
        if known {
            let delta = ProcessCensus.delta(of: instance.rows, since: previousRows)
            evidence.sampleInterval = interval
            // The CPU of an editor says nothing about its agent: the
            // renderer is busy while the user types or scrolls.
            evidence.subtreeCPUSeconds = cursor ? 0 : delta.cpuTime
            evidence.energyNanojoules = delta.energyNanojoules
            evidence.logicalWriteBytes = delta.logicalWriteBytes
        }
        guard instance.rows.count > 1 else { return }
        // A busy process below Cursor is not its agent's unless a turn is
        // in progress: a search of the editor ran at 99 percent of a core
        // while the agent was idle.
        if cursor, evidence.reported?.state != .working { return }
        let byPID = cursor ? Dictionary(instance.rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        let agentPIDs = Set(instance.rows.lazy.map(\.pid).filter { matches[$0] != nil })
        let children = ProcessCensus.childrenIndex(of: instance.rows)
        for row in instance.rows.dropFirst() where !agentPIDs.contains(row.pid) && agentPIDs.contains(row.ppid) {
            if cursor, !(byPID[row.ppid].map { AgentCatalog.isCursorAgentCommand(row, parent: $0) } ?? false) { continue }
            evidence.childCommands += 1
            liveUnits.insert(row.identity)
            // A command of an instance that is new to the collector may be old,
            // and all it ever used would count as one burst.
            guard known else { continue }
            let subtree = ProcessCensus.subtree(of: row, in: children, stoppingAt: agentPIDs)
            let cpu = ProcessCensus.delta(of: subtree, since: previousRows).cpuTime
            var window = childWindows[row.identity] ?? []
            window.append(CPUSample(at: now, cpuSeconds: cpu, interval: interval))
            window.removeAll { now.timeIntervalSince($0.at) >= Self.childWindow || $0.at > now }
            childWindows[row.identity] = window
            let recent = window.filter { now.timeIntervalSince($0.at) < Self.childWindow / 2 }
            let earlier = window.filter { now.timeIntervalSince($0.at) >= Self.childWindow / 2 }
            if Self.isBusy(recent), Self.isBusy(earlier) { evidence.busyChildCommands += 1 }
        }
    }
}
