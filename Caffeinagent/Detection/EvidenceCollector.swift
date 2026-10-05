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

        static func system() -> Sources {
            var sources = Sources(census: SystemProcessCensus(), assertions: SystemPowerAssertions(), power: SystemPowerContext(), openFiles: SystemOpenFiles())
            sources.hookDirectory = HookStateFile.directory()
            sources.claudeSettings = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
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
    /// How often the Codex session tree and a Claude project directory are
    /// listed again to find a new file.
    static let listingAge: TimeInterval = 5
    static let codexIDs: Set<String> = ["codex", "codex-desktop"]
    /// How many samples in a row keep the previous frame while the process
    /// table cannot be read.
    static let heldSamples = 5

    /// One more way to say that remote access is on, next to what
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
    private var previousAt: Date?
    private var lastSample: EvidenceSample?
    private var unreadableTables = 0
    private var previousRows: [ProcessIdentity: ProcessInfoRow] = [:]
    private var childWindows: [ProcessIdentity: [CPUSample]] = [:]
    private var sessionFiles = FileCache<ClaudeSessionState>()
    private var jobFiles = FileCache<ClaudeJobState>()
    private var transcripts = FileCache<ClaudeTranscriptReader.TailParse>()
    private var rolloutTails: CodexRolloutTracker
    private var rolloutCwds: [String: String] = [:]
    private var rolloutListing: (at: Date, files: [CodexRolloutFile])?
    private var transcriptChoices: [ProcessIdentity: (at: Date, path: String?)] = [:]
    private var activityReaders: [String: FileActivityReader] = [:]
    private var hookReader: HookStateReader?
    private var claudeSettingsFiles = FileCache<RemoteAccessDetector.ClaudeSettings>()

    init(sources: Sources = .system()) {
        self.sources = sources
        rolloutTails = CodexRolloutTracker(searchBudget: sources.rolloutSearchBudget)
        hookReader = sources.hookDirectory.map(HookStateReader.init(directory:))
        hookReader?.prepare()
    }

    func collect(userNames: [String] = []) -> EvidenceSample {
        let started = DispatchTime.now().uptimeNanoseconds
        let now = sources.now()
        guard let snapshot = sources.census.snapshot() ?? unreadableTable(now: now, started: started) else {
            return lastSample ?? EvidenceSample(frame: EvidenceFrame(at: now, agents: []))
        }
        let matches = currentMatches(in: snapshot, userNames: userNames)
        let instances = sources.catalog.instances(in: snapshot, matches: matches)
        let asserting = instances.isEmpty ? [] : sources.assertions.assertingPIDs()
        // The CPU a process used before and after a sleep, over an interval
        // that is mostly the sleep, would read as no use at all.
        let gap = SampleGap.length(from: previousAt, to: now) != nil
        let interval = gap ? 0 : previousAt.map { now.timeIntervalSince($0) } ?? 0
        if gap { childWindows.removeAll() }

        var sample = EvidenceSample(frame: EvidenceFrame(at: now, agents: [], context: context(snapshot: snapshot, matches: matches)))
        let hookStates = hookReader?.states(snapshot: snapshot, now: now) ?? [:]
        // A new state file is a new entry in the folder.
        if let hookReader { sample.watchedFiles.insert(hookReader.directory.path) }
        var activities: [String: FileActivity] = [:]
        var rows: [ProcessIdentity: ProcessInfoRow] = [:]
        var liveUnits: Set<ProcessIdentity> = []
        for instance in instances {
            for row in instance.rows { rows[row.identity] = row }
            guard var evidence = agentEvidence(for: instance, matches: matches, now: now, activities: &activities, watched: &sample.watchedFiles) else { continue }
            noteUse(of: instance, matches: matches, interval: interval, now: now, in: &evidence, liveUnits: &liveUnits)
            evidence.ownsSleepAssertion = instance.rows.contains { asserting.contains($0.pid) }
            noteHooks(of: instance, matches: matches, states: hookStates, in: &evidence, watched: &sample.watchedFiles)
            sample.frame.agents.append(evidence)
            sample.roots.insert(instance.identity)
        }

        previousAt = now
        previousRows = rows
        childWindows = childWindows.filter { liveUnits.contains($0.key) }
        activityReaders = activityReaders.filter { activities[$0.key] != nil }
        transcriptChoices = transcriptChoices.filter { sample.roots.contains($0.key) }
        sessionFiles.endSample()
        jobFiles.endSample()
        transcripts.endSample()
        rolloutTails.endSample()
        claudeSettingsFiles.endSample()
        sample.cost = TimeInterval(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        lastSample = sample
        unreadableTables = 0
        return sample
    }

    /// The process table could not be read. That says nothing about the
    /// agents, so the previous frame stands for this sample, with the new
    /// time and no CPU numbers. Nil means: go on with what was kept in
    /// `lastSample`. After `heldSamples` failures in a row the table counts
    /// as empty, and the empty table is returned.
    private func unreadableTable(now: Date, started: UInt64) -> [ProcessInfoRow]? {
        unreadableTables += 1
        guard unreadableTables <= Self.heldSamples, var sample = lastSample else {
            lastSample = nil
            return []
        }
        sample.frame.at = now
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
        return RemoteAccessDetector.claudeRemoteControl(sessions: sessions.map { AgentCatalog.command(of: $0).arguments }, settings: settings)
    }

    /// The state the agent's hooks left for one of the instance's own
    /// processes. A launcher and the binary it starts are one instance, and
    /// the hook runs below either.
    private func noteHooks(
        of instance: AgentInstance, matches: [Int32: AgentMatch], states: [Int32: HookStateReader.State],
        in evidence: inout AgentEvidence, watched: inout Set<String>
    ) {
        guard !states.isEmpty, let hookAgent = HookEvents.hookAgent(forDefinition: instance.definition.id) else { return }
        let own = instance.rows.compactMap { row -> HookStateReader.State? in
            guard let state = states[row.pid], state.agent == hookAgent,
                  let match = matches[row.pid], match.definition.id == instance.definition.id, match.role != .helper else { return nil }
            return state
        }
        guard let newest = own.max(by: { $0.at < $1.at }) else { return }
        evidence.hookState = newest.state
        evidence.hookStateAt = newest.at
        own.forEach { watched.insert($0.path) }
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
        if choice.map({ now.timeIntervalSince($0.at) >= Self.listingAge }) ?? true {
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
            paths = sessionRollout(for: instance, started: started, now: now).map { [$0] } ?? []
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

    /// `codex exec` and the TUI: the newest rollout of the process's working
    /// directory that was written since the process started. Rollouts carry
    /// no pid.
    private func sessionRollout(for instance: AgentInstance, started: Date, now: Date) -> String? {
        if rolloutListing.map({ now.timeIntervalSince($0.at) >= Self.listingAge || $0.at > now }) ?? true {
            rolloutListing = (now, sources.codexRollouts.recentFiles(now: now))
            let listed = Set(rolloutListing?.files.map(\.url.path) ?? [])
            rolloutCwds = rolloutCwds.filter { listed.contains($0.key) }
        }
        let candidates = (rolloutListing?.files ?? []).filter { $0.lastWrite >= started }
        guard !candidates.isEmpty, let cwd = sources.openFiles.workingDirectory(of: instance.rootPID).map(Self.resolved) else { return nil }
        // Newest first, as the listing is.
        for file in candidates {
            let path = file.url.path
            let fileCwd = rolloutCwds[path] ?? CodexRolloutReader.sessionCwd(of: file.url).map(Self.resolved)
            guard let fileCwd else { continue }
            rolloutCwds[path] = fileCwd
            if fileCwd == cwd { return path }
        }
        return nil
    }

    /// `/tmp` and `/private/tmp` are the same directory.
    private static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
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
        if known {
            let delta = ProcessCensus.delta(of: instance.rows, since: previousRows)
            evidence.sampleInterval = interval
            evidence.subtreeCPUSeconds = delta.cpuTime
            evidence.energyNanojoules = delta.energyNanojoules
            evidence.logicalWriteBytes = delta.logicalWriteBytes
        }
        guard instance.rows.count > 1 else { return }
        let agentPIDs = Set(instance.rows.lazy.map(\.pid).filter { matches[$0] != nil })
        let children = ProcessCensus.childrenIndex(of: instance.rows)
        for row in instance.rows.dropFirst() where !agentPIDs.contains(row.pid) && agentPIDs.contains(row.ppid) {
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
