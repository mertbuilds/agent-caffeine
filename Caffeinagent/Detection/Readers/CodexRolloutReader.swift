import Foundation

/// What the tail of a Codex rollout file says about the newest turn.
struct CodexTurnState: Equatable {
    enum Marker: String, Equatable {
        case started = "task_started"
        case completed = "task_complete"
        case aborted = "turn_aborted"
    }

    /// The newest turn marker in the tail. Nil when the tail has none.
    var lastMarker: Marker?
    var turnInProgress = false
    /// When the newest turn started or ended.
    var markerAt: Date?
    var turnID: String?
    /// From the newest `turn_context` record in the tail.
    var cwd: String?

    var state: ReportedState? {
        guard lastMarker != nil else { return nil }
        return turnInProgress ? .working : .idle
    }
}

struct CodexRolloutFile: Equatable {
    var url: URL
    /// The thread id, the last 36 characters of the file name.
    var sessionID: String?
    var lastWrite: Date
    var size: UInt64
}

struct CodexRollout: Equatable {
    var file: CodexRolloutFile
    /// From the `session_meta` record, else the newest `turn_context`. It
    /// labels the agent; it does not name a process.
    var cwd: String?
    var turn: CodexTurnState
}

/// Reads `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<thread id>.jsonl`.
///
/// A rollout cannot say that Codex waits for an approval or an answer: those
/// requests are not written to the file, so a waiting turn looks the same as
/// a working, silent one. The waiting state for Codex comes from its hooks.
///
/// A killed Codex leaves a `task_started` with no end. The caller treats
/// "working" as true only while a Codex process is alive, and should prefer
/// a file that such a process holds open.
///
/// Rollouts carry no pid. `codex exec` is one process per file, so its cwd
/// matches. Interactive sessions run inside a shared app-server (the managed
/// daemon, or the one inside ChatGPT.app) that owns many threads, so a file
/// maps to that server through its open file descriptors, never to one TUI.
struct CodexRolloutReader {
    var sessionsDirectory: URL

    init(sessionsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")) {
        self.sessionsDirectory = sessionsDirectory
    }

    /// Rollout files written within `maxAge`, newest first. The date in the
    /// path is the day the thread began, so every directory is listed.
    func recentFiles(maxAge: TimeInterval = 86_400, now: Date = Date()) -> [CodexRolloutFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: sessionsDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var files: [CodexRolloutFile] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("rollout-"), url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let lastWrite = values.contentModificationDate,
                  now.timeIntervalSince(lastWrite) <= maxAge else { continue }
            files.append(CodexRolloutFile(
                url: url,
                sessionID: Self.sessionID(fromFileName: name),
                lastWrite: lastWrite,
                size: UInt64(max(values.fileSize ?? 0, 0))
            ))
        }
        return files.sorted { $0.lastWrite > $1.lastWrite }
    }

    func rollouts(maxAge: TimeInterval = 86_400, now: Date = Date()) -> [CodexRollout] {
        recentFiles(maxAge: maxAge, now: now).map(Self.rollout(for:))
    }

    nonisolated static func rollout(for file: CodexRolloutFile) -> CodexRollout {
        let turn = parseTail(of: file.url)
        return CodexRollout(file: file, cwd: sessionCwd(of: file.url) ?? turn.cwd, turn: turn)
    }

    /// Nil when the tail holds no turn marker.
    nonisolated static func report(for rollout: CodexRollout, now: Date = Date()) -> StateReport? {
        guard let state = rollout.turn.state else { return nil }
        return StateReport(
            state: state,
            since: rollout.turn.markerAt,
            observedAt: now,
            source: .codexRollout,
            detail: state == .working ? "in a turn" : nil
        )
    }

    nonisolated static func sessionID(fromFileName name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        let id = String(stem.suffix(36))
        return UUID(uuidString: id) == nil ? nil : id
    }

    /// Reads the last 64KB. One long record, such as a big tool output, can
    /// fill that window, so without a turn marker in it the last 1MB is read.
    nonisolated static func parseTail(of url: URL) -> CodexTurnState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return CodexTurnState() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return CodexTurnState() }
        var result = CodexTurnState()
        for chunk: UInt64 in [65_536, 1_048_576] {
            let offset = size > chunk ? size - chunk : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return CodexTurnState() }
            result = parseTail(String(decoding: data, as: UTF8.self))
            if result.lastMarker != nil || offset == 0 { break }
        }
        return result
    }

    /// Each line is `{timestamp, type, payload}`. Turn markers are `event_msg`
    /// records whose `payload.type` is `task_started`, `task_complete` or
    /// `turn_aborted`. The newest `task_started` is in progress unless a later
    /// end marker carries its `turn_id`, or carries none. An end marker of an
    /// older turn, as when a new turn replaces a running one, does not close it.
    nonisolated static func parseTail(_ text: String) -> CodexTurnState {
        var result = CodexTurnState()
        var endedTurns: Set<String> = []
        var endedWithoutID = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = record["type"] as? String,
                  let payload = record["payload"] as? [String: Any] else { continue }
            if type == "turn_context" {
                if result.cwd == nil { result.cwd = payload["cwd"] as? String }
                continue
            }
            guard type == "event_msg",
                  let marker = (payload["type"] as? String).flatMap(CodexTurnState.Marker.init(rawValue:)) else { continue }
            let turnID = payload["turn_id"] as? String
            if result.lastMarker == nil {
                result.lastMarker = marker
                result.turnID = turnID
                let own = marker == .started ? payload["started_at"] : payload["completed_at"]
                result.markerAt = ReportedTime.date(own) ?? ReportedTime.date(record["timestamp"])
            }
            if marker == .started {
                if let turnID {
                    result.turnInProgress = !endedWithoutID && !endedTurns.contains(turnID)
                } else {
                    result.turnInProgress = !endedWithoutID && endedTurns.isEmpty
                }
                if result.turnInProgress, result.lastMarker != .started {
                    result.lastMarker = .started
                    result.turnID = turnID
                    result.markerAt = ReportedTime.date(payload["started_at"]) ?? ReportedTime.date(record["timestamp"])
                }
                break
            }
            if let turnID { endedTurns.insert(turnID) } else { endedWithoutID = true }
        }
        return result
    }

    /// The `cwd` of the `session_meta` record, the first line of the file.
    /// That line also holds the full base instructions (about 20KB here), so
    /// the head is read up to 512KB before giving up.
    nonisolated static func sessionCwd(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        for chunk in [65_536, 524_288] {
            try? handle.seek(toOffset: 0)
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { return nil }
            if let end = data.firstIndex(of: UInt8(ascii: "\n")) {
                return sessionCwd(firstLine: data[data.startIndex..<end])
            }
            if data.count < chunk { return sessionCwd(firstLine: data) }
        }
        return nil
    }

    nonisolated static func sessionCwd(firstLine: Data) -> String? {
        guard let record = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
              record["type"] as? String == "session_meta" else { return nil }
        return (record["payload"] as? [String: Any])?["cwd"] as? String
    }
}
