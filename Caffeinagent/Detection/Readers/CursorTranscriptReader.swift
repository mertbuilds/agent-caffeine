import Foundation

/// What a Cursor agent transcript says about its newest turn.
struct CursorTurnState: Equatable {
    enum Status: String, Equatable {
        case success
        case error
        case aborted
        /// A status this build does not know.
        case other
    }

    enum Line: Equatable {
        case user
        case assistant
        case turnEnded(Status)
    }

    /// The newest line of a known type. Nil when none was found.
    var last: Line?

    var turnInProgress: Bool { last == .user || last == .assistant }

    /// How the newest turn ended. Nil while it runs.
    var endStatus: Status? {
        if case .turnEnded(let status)? = last { return status }
        return nil
    }

    var state: ReportedState? {
        guard last != nil else { return nil }
        return turnInProgress ? .working : .idle
    }
}

struct CursorTranscriptFile: Equatable {
    var url: URL
    /// The conversation id, from the file name.
    var sessionID: String?
    /// The folder name below `projects`.
    var projectSlug: String
    var lastWrite: Date
    var size: UInt64
}

/// Reads `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`, the
/// transcript the Cursor editor's agent writes per conversation
/// (docs/research/08-cursor.md). An older Cursor wrote
/// `agent-transcripts/<id>.jsonl`, and that is read too. The transcripts of
/// subagents are one folder deeper and are left out: a subagent that stops
/// does not end the turn.
///
/// The lines are `{"role":"user"|"assistant",...}` and
/// `{"type":"turn_ended","status":...}`. They carry no time. A turn is in
/// progress when the newest line is no `turn_ended`.
///
/// The file is not written while a long command runs, so the age of the
/// last write says nothing about idle. Cursor can write the whole file
/// anew, so no offset is kept: the tail is read again after each change.
///
/// A transcript cannot say that Cursor waits for an approval. That is
/// inferred in `CursorApprovalRule`.
///
/// A killed Cursor leaves a turn that never ends. The caller counts a file
/// only when it was written after the Cursor process started.
struct CursorTranscriptReader {
    var projectsDirectory: URL

    static let transcriptsFolder = "agent-transcripts"
    static let emptyWindowSlug = "empty-window"

    init(projectsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cursor/projects")) {
        self.projectsDirectory = projectsDirectory
    }

    /// Transcripts written within `maxAge`, newest first.
    func recentFiles(maxAge: TimeInterval = 86_400, now: Date = Date()) -> [CursorTranscriptFile] {
        let manager = FileManager.default
        var files: [CursorTranscriptFile] = []
        func note(_ url: URL, slug: String) {
            guard url.pathExtension == "jsonl", let signature = FileSignature(path: url.path),
                  now.timeIntervalSince(signature.modifiedAt) <= maxAge else { return }
            files.append(CursorTranscriptFile(
                url: url, sessionID: Self.sessionID(fromFileName: url.lastPathComponent), projectSlug: slug,
                lastWrite: signature.modifiedAt, size: signature.size
            ))
        }
        for slug in (try? manager.contentsOfDirectory(atPath: projectsDirectory.path)) ?? [] where !slug.hasPrefix(".") {
            let folder = projectsDirectory.appendingPathComponent(slug).appendingPathComponent(Self.transcriptsFolder)
            for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where !name.hasPrefix(".") {
                let entry = folder.appendingPathComponent(name)
                if name.hasSuffix(".jsonl") {
                    note(entry, slug: slug)
                } else {
                    note(entry.appendingPathComponent(name + ".jsonl"), slug: slug)
                }
            }
        }
        return files.sorted { $0.lastWrite > $1.lastWrite }
    }

    nonisolated static func sessionID(fromFileName name: String) -> String? {
        let stem = name.hasSuffix(".jsonl") ? String(name.dropLast(6)) : name
        return UUID(uuidString: stem) == nil ? nil : stem
    }

    // MARK: Parsing

    /// One line can hold a whole file that the agent wrote, so the tail is
    /// read in steps until a line of a known type is in it.
    static let tailSteps: [UInt64] = [65_536, 1_048_576, 8 * 1_048_576]

    nonisolated static func parseTail(of url: URL) -> CursorTurnState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return CursorTurnState() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return CursorTurnState() }
        for step in tailSteps {
            let offset = size > step ? size - step : 0
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return CursorTurnState() }
            let turn = parseTail(data, fromStart: offset == 0)
            if turn.last != nil || offset == 0 { return turn }
        }
        return CursorTurnState()
    }

    nonisolated static func parseTail(_ text: String) -> CursorTurnState {
        parseTail(Data(text.utf8), fromStart: true)
    }

    /// The newest line of a known type decides. A line of another type is
    /// passed over, and so is a last line that is cut off in the middle of
    /// a write. `fromStart` is false when the data begins inside a line.
    nonisolated static func parseTail(_ data: Data, fromStart: Bool) -> CursorTurnState {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)[...]
        if !fromStart { lines = lines.dropFirst() }
        for line in lines.reversed() where !line.isEmpty {
            if let known = kind(of: line) { return CursorTurnState(last: known) }
        }
        return CursorTurnState()
    }

    /// Only the `role`, `type` and `status` of a line are looked at. The
    /// message is never kept.
    nonisolated static func kind(of data: Data) -> CursorTurnState.Line? {
        guard let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if record["type"] as? String == "turn_ended" {
            let status = (record["status"] as? String).flatMap(CursorTurnState.Status.init(rawValue:)) ?? .other
            return .turnEnded(status)
        }
        switch record["role"] as? String {
        case "user": return .user
        case "assistant": return .assistant
        default: return nil
        }
    }

    // MARK: Project

    /// Cursor names a project folder after the workspace path: every
    /// character that is no ASCII letter or digit becomes `-`, a row of
    /// them is one, and none stays at the ends.
    nonisolated static func slug(forWorkspace path: String) -> String {
        var slug = ""
        for scalar in path.unicodeScalars {
            let keep = scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
            if keep {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    /// A name for the menu. A slug cannot be turned back into a path:
    /// `my-app`, `my.app` and `my/app` give the same slug. So the label is
    /// the last part of the slug, which is the folder name when that name
    /// has letters and digits only, and the end of it otherwise. Nil for
    /// a window with no folder.
    nonisolated static func label(forSlug slug: String) -> String? {
        guard slug != emptyWindowSlug, let last = slug.split(separator: "-").last else { return nil }
        return String(last)
    }
}

/// Follows the transcripts from one sample to the next. A file with the
/// same signature is not read again. The lines carry no time, so the start
/// of a turn is the write time of the file when its newest line is the
/// user's message, and that time is kept while the turn runs.
struct CursorTranscriptTracker {
    struct Reading: Equatable {
        var turn: CursorTurnState
        /// When the turn in progress began. Nil when the turn began before
        /// the file was first read, and when no turn runs.
        var turnSince: Date?
        var signature: FileSignature
    }

    private var entries: [String: Reading] = [:]
    private var used: Set<String> = []

    /// Nil when the file is missing.
    mutating func read(path: String) -> Reading? {
        guard let signature = FileSignature(path: path) else {
            entries[path] = nil
            return nil
        }
        used.insert(path)
        let known = entries[path]
        if let known, known.signature == signature { return known }
        let turn = CursorTranscriptReader.parseTail(of: URL(fileURLWithPath: path))
        var reading = Reading(turn: turn, turnSince: nil, signature: signature)
        if turn.turnInProgress {
            let running = known?.turn.turnInProgress == true ? known?.turnSince : nil
            reading.turnSince = running ?? (turn.last == .user ? signature.modifiedAt : nil)
        }
        entries[path] = reading
        return reading
    }

    /// Drops the files no read asked for.
    mutating func endSample() {
        if entries.count != used.count { entries = entries.filter { used.contains($0.key) } }
        used.removeAll(keepingCapacity: true)
    }
}

/// What all transcripts together say about one running Cursor.
struct CursorSummary: Equatable {
    /// The files that were written since this Cursor started.
    var counted = 0
    /// The counted files with a turn in progress.
    var inTurn = 0
    /// A counted file has no line of a known type.
    var unknown = false
    /// When the oldest turn in progress began, where that is known.
    var workingSince: Date?
    var newestWrite: Date?
    /// The newest write of a file whose turn has ended.
    var newestEnd: Date?
    /// The project of the turn in progress, else of the newest transcript.
    var projectSlug: String?

    var working: Bool { inTurn > 0 }

    /// Only a file this Cursor process wrote can hold a turn of this
    /// process: a Cursor that was killed leaves a turn that never ends.
    /// `readings` is newest first.
    static func make(of readings: [(file: CursorTranscriptFile, reading: CursorTranscriptTracker.Reading)], engineStarted: Date) -> CursorSummary {
        var summary = CursorSummary()
        var workingSlug: String?
        for (file, reading) in readings where reading.signature.modifiedAt >= engineStarted {
            let written = reading.signature.modifiedAt
            summary.counted += 1
            summary.newestWrite = max(summary.newestWrite ?? written, written)
            if summary.projectSlug == nil { summary.projectSlug = file.projectSlug }
            guard reading.turn.last != nil else {
                summary.unknown = true
                continue
            }
            if reading.turn.turnInProgress {
                summary.inTurn += 1
                if workingSlug == nil { workingSlug = file.projectSlug }
                if let since = reading.turnSince { summary.workingSince = min(summary.workingSince ?? since, since) }
            } else {
                summary.newestEnd = max(summary.newestEnd ?? written, written)
            }
        }
        summary.projectSlug = workingSlug ?? summary.projectSlug
        return summary
    }

    /// Working while any conversation is in a turn. Idle only when every
    /// counted file was understood. Nil with no counted file: Cursor can
    /// run with transcripts switched off, and then the signs of activity
    /// decide.
    func report(now: Date) -> StateReport? {
        if working {
            return StateReport(state: .working, since: workingSince, observedAt: now, source: .cursorTranscript, detail: "in a turn")
        }
        guard counted > 0, !unknown else { return nil }
        return StateReport(state: .idle, since: newestEnd, observedAt: now, source: .cursorTranscript, detail: nil)
    }
}
