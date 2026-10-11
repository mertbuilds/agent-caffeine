import Foundation

/// One `~/.claude/sessions/<pid>.json`, the file a live Claude Code process
/// keeps about itself and removes at exit.
struct ClaudeSessionState: Equatable {
    enum Kind: Equatable {
        case interactive
        /// `kind: "bg"`: a background session that a daemon spare took over.
        case background
        /// A pre-started process that has no job yet (`spare` key present).
        case spare
        case other(String)
    }

    var state: ReportedState
    /// `status: "shell"`: the turn is over, and background commands of the
    /// session still run. The state is idle then. See
    /// `StateReport.backgroundWork`.
    var backgroundWork = false
    /// The `status` string as written: `busy`, `shell`, `waiting` or `idle`.
    var rawStatus: String
    /// Not refreshed inside a long turn, and days old on an idle session.
    var statusUpdatedAt: Date?
    /// The pid the file names. The file outlives a crashed process, so the
    /// caller checks that this pid is alive before it trusts the state.
    var pid: Int32?
    var kind: Kind?
    var sessionID: String?
    /// Names the directory in `~/.claude/jobs` of a background session.
    var jobID: String?
    var cwd: String?
    var version: String?
    /// `entrypoint`: `cli` for a terminal, `claude-desktop` for a session
    /// of the Claude app's Code tab.
    var entrypoint: String?
    /// `name`: the session's own name. It can come from what the user
    /// typed, so it is for the menu only and never part of a report.
    var name: String?
    var observedAt: Date

    var report: StateReport {
        StateReport(state: state, since: statusUpdatedAt, observedAt: observedAt, source: .claudeSessionFile, detail: detail, backgroundWork: backgroundWork)
    }

    private var detail: String? {
        switch rawStatus {
        case "busy": return "in a turn"
        case "shell": return "turn ended, background commands run"
        case "waiting": return "waiting for you"
        default: return nil
        }
    }
}

struct ClaudeSessionStateReader {
    var sessionsDirectory: URL

    init(sessionsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")) {
        self.sessionsDirectory = sessionsDirectory
    }

    func fileURL(forPid pid: Int32) -> URL {
        sessionsDirectory.appendingPathComponent("\(pid).json")
    }

    /// Nil when the file is missing, is not understood, or names another pid.
    func state(forPid pid: Int32, now: Date = Date()) -> ClaudeSessionState? {
        guard let data = Self.smallFile(at: fileURL(forPid: pid)),
              var state = Self.parse(data, now: now) else { return nil }
        if let filePid = state.pid, filePid != pid { return nil }
        state.pid = pid
        return state
    }

    func report(forPid pid: Int32, now: Date = Date()) -> StateReport? {
        state(forPid: pid, now: now)?.report
    }

    /// Every readable session file. Files of dead processes are included.
    func allStates(now: Date = Date()) -> [ClaudeSessionState] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "json", let pid = Int32(url.deletingPathExtension().lastPathComponent) else { return nil }
            return state(forPid: pid, now: now)
        }
    }

    /// The format is undocumented, so every key is optional except `status`
    /// (written since Claude Code 2.1.119, per other projects). `busy` and
    /// `idle` were seen on this Mac on 2.1.286 to 2.1.289, `waiting` in an
    /// earlier measurement, and `shell` (the turn ended, background
    /// commands still run) on 2.1.289. A session of the Claude app writes
    /// `busy`, `waiting` and `idle` only (docs/research/09-claude-desktop.md).
    ///
    /// `shell` is not `busy`. On 2026-10-10 a session stayed at `shell`
    /// for 13.7 hours for a dev server at 0.0 percent CPU, and as a
    /// working it kept a Mac awake in a bag for that long
    /// (docs/research/01-oss-detection.md, section 9).
    nonisolated static func parse(_ data: Data, now: Date) -> ClaudeSessionState? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String else { return nil }
        let state: ReportedState
        switch status {
        case "busy": state = .working
        case "waiting": state = .waitingForUser
        case "shell", "idle": state = .idle
        default: return nil
        }
        return ClaudeSessionState(
            state: state,
            backgroundWork: status == "shell",
            rawStatus: status,
            statusUpdatedAt: ReportedTime.date(object["statusUpdatedAt"]) ?? ReportedTime.date(object["updatedAt"]),
            pid: (object["pid"] as? Int).flatMap(Int32.init(exactly:)),
            kind: kind(object),
            sessionID: object["sessionId"] as? String,
            jobID: object["jobId"] as? String,
            cwd: object["cwd"] as? String,
            version: object["version"] as? String,
            entrypoint: object["entrypoint"] as? String,
            name: SessionHint.cleaned(name: object["name"] as? String),
            observedAt: now
        )
    }

    nonisolated private static func kind(_ object: [String: Any]) -> ClaudeSessionState.Kind? {
        if let spare = object["spare"], !(spare is NSNull), spare as? Bool != false { return .spare }
        switch object["kind"] as? String {
        case "interactive": return .interactive
        case "bg": return .background
        case let other?: return .other(other)
        case nil: return nil
        }
    }

    nonisolated static func smallFile(at url: URL, limit: Int = 1_048_576) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
}

/// `~/.claude/jobs/<id>/state.json`, kept per background job. It has no pid:
/// a session file points at it with `jobId`, and it names its `sessionId`.
/// The directory stays after the job ends, so `done` files pile up.
struct ClaudeJobState: Equatable {
    enum Phase: String, Equatable {
        case working
        case blocked
        case done
    }

    var phase: Phase
    /// `inFlight.tasks`: background shells and subagents still running.
    var tasksInFlight: Int
    var updatedAt: Date?
    var sessionID: String?
    var cwd: String?
    var observedAt: Date

    var isFinished: Bool { phase == .done }

    /// `blocked` with tasks in flight was seen on a job whose session file
    /// said `busy`, so it counts as working. `blocked` with nothing in flight
    /// is taken as waiting for the user; that reading is not confirmed.
    var state: ReportedState {
        switch phase {
        case .working: return .working
        case .blocked: return tasksInFlight > 0 ? .working : .waitingForUser
        case .done: return .idle
        }
    }

    var report: StateReport {
        let detail: String?
        switch state {
        case .working: detail = phase == .blocked ? "background tasks running" : "background job running"
        case .waitingForUser: detail = "background job waiting for you"
        case .idle: detail = nil
        }
        return StateReport(state: state, since: updatedAt, observedAt: observedAt, source: .claudeJobState, detail: detail)
    }
}

struct ClaudeJobStateReader {
    var jobsDirectory: URL

    init(jobsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/jobs")) {
        self.jobsDirectory = jobsDirectory
    }

    func state(forJobID jobID: String, now: Date = Date()) -> ClaudeJobState? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !jobID.isEmpty, jobID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let url = jobsDirectory.appendingPathComponent(jobID).appendingPathComponent("state.json")
        return ClaudeSessionStateReader.smallFile(at: url).flatMap { Self.parse($0, now: now) }
    }

    /// `state` values seen on this Mac: `working`, `blocked`, `done`. Other
    /// keys (`tempo`, `detail`, `output`, ...) are not read.
    nonisolated static func parse(_ data: Data, now: Date) -> ClaudeJobState? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let phase = (object["state"] as? String).flatMap(ClaudeJobState.Phase.init(rawValue:)) else { return nil }
        return ClaudeJobState(
            phase: phase,
            tasksInFlight: ((object["inFlight"] as? [String: Any])?["tasks"] as? Int) ?? 0,
            updatedAt: ReportedTime.date(object["updatedAt"]),
            sessionID: object["sessionId"] as? String,
            cwd: object["cwd"] as? String,
            observedAt: now
        )
    }
}
