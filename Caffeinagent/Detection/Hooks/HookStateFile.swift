import Foundation

/// The file the hook command leaves for one agent process:
/// `<hook agent id>-<pid>.json` in the hooks folder. It holds a state per
/// session, because one Codex engine runs many threads and a file with one
/// state would let the thread that stops hide the thread that still works.
/// A session is stored under a hash of its id. Nothing the user typed, no
/// tool argument and no path is stored.
struct HookStateFile: Codable, Equatable {
    static let currentVersion = 1
    static let maxSessions = 64
    static let sessionLifetime: TimeInterval = 24 * 3600
    static let directoryOverrideKey = "CAFFEINAGENT_HOOKS_DIR"
    /// Two hook commands that started this close together can finish out
    /// of order. A state that is further ahead of the clock than this was
    /// written before the clock was set back.
    static let clockTolerance: TimeInterval = 5

    struct Session: Codable, Equatable {
        /// `working`, `waiting` or `idle`.
        var state: String
        /// The name of the event, from `HookEvents.rules`.
        var event: String
        /// Seconds since the epoch.
        var at: TimeInterval
    }

    var v = HookStateFile.currentVersion
    var agent: String
    var pid: Int32
    /// Start time of the agent process, as in `ProcessInfoRow`.
    var start: TimeInterval
    var sessions: [String: Session] = [:]

    /// The override is for tests and the lab, so they never write into the
    /// folder the app reads.
    static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment[directoryOverrideKey], !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/\(HookEvents.bundleID)/hooks", isDirectory: true)
    }

    static func fileName(agent: String, pid: Int32) -> String { "\(agent)-\(pid).json" }

    /// FNV-1a, 64 bit. Enough to tell the sessions of one process apart.
    static func sessionKey(_ sessionID: String?) -> String {
        guard let sessionID, !sessionID.isEmpty else { return "none" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in sessionID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    static func name(of state: ReportedState) -> String {
        switch state {
        case .working: return "working"
        case .waitingForUser: return "waiting"
        case .idle: return "idle"
        }
    }

    static func state(named name: String) -> ReportedState? {
        switch name {
        case "working": return .working
        case "waiting": return .waitingForUser
        case "idle": return .idle
        default: return nil
        }
    }

    /// The events of a session count in the order they arrive: the hook
    /// command reads, changes and writes the file under one lock. Only an
    /// event that is a moment older than what the session holds is
    /// dropped, because two hook commands can finish out of order. What
    /// the session holds from further ahead is from before the clock was
    /// set back, and the new event replaces it.
    mutating func apply(_ action: HookAction, session: String, event: String, at: Date) {
        let time = at.timeIntervalSince1970
        switch action {
        case .ignore:
            return
        case .end:
            sessions[session] = nil
        case .set(let state):
            if let known = sessions[session], known.at > time, known.at - time <= Self.clockTolerance { return }
            sessions[session] = Session(state: Self.name(of: state), event: event, at: time)
        }
        sessions = sessions.filter { abs(time - $0.value.at) < Self.sessionLifetime }
        if sessions.count > Self.maxSessions {
            let kept = sessions.sorted { $0.value.at > $1.value.at }.prefix(Self.maxSessions)
            sessions = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }

    /// One state for the process. Among the sessions that reported within
    /// `freshness`, working wins over waiting and waiting over idle, so a
    /// session that never sent its last event cannot hide a live one. A
    /// session that waits for the user counts at any age: the wait ends
    /// with its next event, not with time. With no such session it is the
    /// newest one. The verdict finds it too old to use, but for the idle
    /// of an agent with no state of its own: `VerdictRules.noteHookIdle`.
    ///
    /// A working that is no longer fresh stands before a wait or an idle
    /// of another session for `workingLimit`: a long tool call sends no
    /// event, so that session may still work. It is given with its real
    /// time, and the verdict decides what a working of that age is worth:
    /// the agent's own state, where it has one. After `workingLimit` its
    /// last event is taken for lost, and the other sessions count again.
    ///
    /// A state from ahead of the clock is from before the clock was set
    /// back. It is as good as too old.
    func summary(now: Date, freshness: TimeInterval, workingLimit: TimeInterval) -> (state: ReportedState, at: Date)? {
        let known = sessions.values.compactMap { session in
            Self.state(named: session.state).map { (state: $0, at: Date(timeIntervalSince1970: session.at)) }
        }
        let live = known.filter { state in
            let age = now.timeIntervalSince(state.at)
            guard age >= -Self.clockTolerance else { return false }
            switch state.state {
            case .waitingForUser: return true
            case .working: return age <= max(freshness, workingLimit)
            case .idle: return age <= freshness
            }
        }
        for state in [ReportedState.working, .waitingForUser, .idle] {
            if let newest = live.filter({ $0.state == state }).max(by: { $0.at < $1.at }) { return newest }
        }
        return known.max { $0.at < $1.at }
    }
}

/// Reads the few fields the hook command needs from the JSON an agent sends
/// on stdin, without building the document: the input can hold a whole
/// prompt or a tool result, and it can be cut off at the read limit.
enum HookInput {
    /// Cursor names its session `conversation_id`.
    static let sessionKeys: [String] = ["session_id", "sessionID", "sessionId", "conversation_id"]
    static let wantedKeys: Set<String> = Set(sessionKeys + ["notification_type", "agent_id"])
    static let maxValueBytes = 256

    /// The string values of the wanted keys of the top-level object. A value
    /// that is no string, is too long or is cut off is left out.
    static func topLevelStrings(in bytes: [UInt8], keys: Set<String> = wantedKeys) -> [String: String] {
        var found: [String: String] = [:]
        var index = 0
        var depth = 0
        var expectsKey = false
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")

        func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0a, 0x0d].contains(bytes[index]) { index += 1 }
        }
        /// `index` is on the opening quote and ends after the closing one.
        /// Nil when the string is cut off or longer than `limit`.
        func readString(limit: Int) -> String? {
            index += 1
            let start = index
            while index < bytes.count {
                if bytes[index] == backslash {
                    index += 2
                } else if bytes[index] == quote {
                    let end = index
                    index += 1
                    return end - start <= limit ? String(decoding: bytes[start..<end], as: UTF8.self) : nil
                } else {
                    index += 1
                }
            }
            return nil
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                guard depth == 1, expectsKey else {
                    _ = readString(limit: 0)
                    continue
                }
                expectsKey = false
                let key = readString(limit: 64)
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { continue }
                index += 1
                skipSpace()
                guard index < bytes.count, bytes[index] == quote else { continue }
                let wanted = key.map(keys.contains) ?? false
                let value = readString(limit: wanted ? maxValueBytes : 0)
                if wanted, let key, let value { found[key] = value }
                continue
            }
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                depth += 1
                if depth == 1 { expectsKey = byte == UInt8(ascii: "{") }
            } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                depth -= 1
            } else if byte == UInt8(ascii: ","), depth == 1 {
                expectsKey = true
            }
            index += 1
        }
        return found
    }
}
