import Foundation

/// What a Codex rollout file says about its newest turn.
struct CodexTurnState: Equatable {
    enum Marker: String, Equatable {
        case started = "task_started"
        case completed = "task_complete"
        case aborted = "turn_aborted"
    }

    /// The newest turn marker. Nil when none was found.
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

    /// Takes the next marker in file order. The end of an older turn does
    /// not close the turn that runs.
    mutating func note(_ marker: Marker, turnID id: String?, at: Date?) {
        if marker != .started, turnInProgress, let id, let open = turnID, id != open { return }
        lastMarker = marker
        turnID = id
        markerAt = at
        turnInProgress = marker == .started
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

    /// The newest turn of the whole file, however long the turn is. For one
    /// read with no memory; the collector keeps a `CodexRolloutTracker`.
    nonisolated static func parseTail(of url: URL) -> CodexTurnState {
        var tracker = CodexRolloutTracker(searchBudget: .max)
        return tracker.read(path: url.path)?.turn ?? CodexTurnState()
    }

    /// Each line is `{timestamp, type, payload}`. Turn markers are `event_msg`
    /// records whose `payload.type` is `task_started`, `task_complete` or
    /// `turn_aborted`. The newest `task_started` is in progress unless a later
    /// end marker carries its `turn_id`, or carries none. An end marker of an
    /// older turn, as when a new turn replaces a running one, does not close it.
    nonisolated static func parseTail(_ text: String) -> CodexTurnState {
        parseTail(lines: text.split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) })
    }

    /// The lines are in file order and are read from the newest back.
    nonisolated static func parseTail<Lines: BidirectionalCollection>(lines: Lines) -> CodexTurnState where Lines.Element == Data {
        var scan = BackwardScan()
        for line in lines.reversed() {
            scan.take(line)
            if scan.settled { break }
        }
        return scan.turn
    }

    /// The search from the newest line back, one line at a time, so it can
    /// go on over as many pieces of a file as it takes. Only a
    /// `task_started` settles it: an end marker can be the end of an older
    /// turn, written after the start of the turn that runs.
    struct BackwardScan {
        private(set) var turn = CodexTurnState()
        private(set) var settled = false
        private var endedTurns: Set<String> = []
        private var endedWithoutID = false

        mutating func take(_ line: Data) {
            guard !settled, let record = CodexRolloutReader.record(in: line) else { return }
            switch record {
            case .context(let cwd):
                if turn.cwd == nil { turn.cwd = cwd }
            case .marker(let marker, let turnID, let at):
                if turn.lastMarker == nil {
                    turn.lastMarker = marker
                    turn.turnID = turnID
                    turn.markerAt = at
                }
                guard marker == .started else {
                    if let turnID { endedTurns.insert(turnID) } else { endedWithoutID = true }
                    return
                }
                if let turnID {
                    turn.turnInProgress = !endedWithoutID && !endedTurns.contains(turnID)
                } else {
                    turn.turnInProgress = !endedWithoutID && endedTurns.isEmpty
                }
                if turn.turnInProgress, turn.lastMarker != .started {
                    turn.lastMarker = .started
                    turn.turnID = turnID
                    turn.markerAt = at
                }
                settled = true
            }
        }
    }

    enum Record {
        case marker(CodexTurnState.Marker, turnID: String?, at: Date?)
        case context(cwd: String?)
    }

    private static let eventNeedle = Data("event_msg".utf8)
    private static let contextNeedle = Data("turn_context".utf8)

    /// Nil for a line that is no turn marker and no `turn_context`. Most
    /// lines are neither, and some are megabytes of tool output, so a line
    /// is parsed only when it holds one of the two type names.
    nonisolated static func record(in line: Data) -> Record? {
        guard line.range(of: eventNeedle) != nil || line.range(of: contextNeedle) != nil,
              let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return nil }
        if type == "turn_context" { return .context(cwd: payload["cwd"] as? String) }
        guard type == "event_msg",
              let marker = (payload["type"] as? String).flatMap(CodexTurnState.Marker.init(rawValue:)) else { return nil }
        let own = marker == .started ? payload["started_at"] : payload["completed_at"]
        return .marker(marker, turnID: payload["turn_id"] as? String, at: ReportedTime.date(own) ?? ReportedTime.date(record["timestamp"]))
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

/// Follows rollout files from one sample to the next, so a turn of any
/// length keeps its state: one turn can write many megabytes after its
/// `task_started`, and then no tail of a fixed size holds a marker.
///
/// A file that is new to the tracker is searched from its end backwards
/// until a `task_started` or the start of the file. An end marker alone
/// does not end the search: the start of the turn that runs can be before
/// the end marker of an older turn, in the piece that is read next. After that only the bytes
/// that were appended are parsed. The backward search of one sample is
/// bounded, and a file whose search is not done reads as not resolved:
/// the caller must not take that for idle.
struct CodexRolloutTracker {
    struct Reading: Equatable {
        var turn: CodexTurnState
        /// False while the search for the newest marker is under way, or the
        /// file could not be read. The turn is unknown then.
        var resolved: Bool
        var signature: FileSignature
    }

    /// A file that ends in a marker resolves in this first read.
    static let firstChunk: UInt64 = 65_536
    static let chunk: UInt64 = 1_048_576
    /// Bytes of backward search per sample, over all files, after the first
    /// read of each. About 10 ms of work on the test Mac.
    static let defaultSearchBudget: UInt64 = 8 * 1_048_576
    /// More than this appended between two samples is searched from the end again.
    static let longestAppend: UInt64 = 8 * 1_048_576
    /// No marker line is this long. A longer line is not kept in memory.
    static let longestKeptLine = 4 * 1_048_576
    private static let anchorLength = 64
    private static let newline = UInt8(ascii: "\n")

    private struct Entry {
        var signature: FileSignature
        var turn = CodexTurnState()
        var resolved = false
        /// The end of the last whole line that was parsed.
        var offset: UInt64
        /// The bytes before `offset`. When they change, the file was written anew.
        var anchor = Data()
        /// Where the backward search stands. Nil before its first read.
        var searchedFrom: UInt64?
        /// The start of the search area up to its first line end: the tail
        /// of a line that begins further back.
        var carry = Data()
        var carryDropped = false
        /// What the backward search has seen so far.
        var scan = CodexRolloutReader.BackwardScan()
    }

    var searchBudget: UInt64
    private var budgetLeft: UInt64
    private var entries: [String: Entry] = [:]
    private var used: Set<String> = []

    init(searchBudget: UInt64 = CodexRolloutTracker.defaultSearchBudget) {
        self.searchBudget = searchBudget
        budgetLeft = searchBudget
    }

    /// Nil when the file is missing.
    mutating func read(path: String) -> Reading? {
        guard let signature = FileSignature(path: path) else {
            entries[path] = nil
            return nil
        }
        used.insert(path)
        if let entry = entries[path], entry.resolved, entry.signature == signature {
            return Reading(turn: entry.turn, resolved: true, signature: signature)
        }
        guard let handle = FileHandle(forReadingAtPath: path) else {
            entries[path] = nil
            return Reading(turn: CodexTurnState(), resolved: false, signature: signature)
        }
        defer { try? handle.close() }

        var entry = entries[path].flatMap { Self.appended(to: $0, signature: signature, handle: handle) }
            ?? Entry(signature: signature, offset: signature.size)
        entry.signature = signature
        search(&entry, handle: handle)
        entries[path] = entry
        return Reading(turn: entry.turn, resolved: entry.resolved, signature: signature)
    }

    /// Drops the files no read asked for and opens the next sample's budget.
    mutating func endSample() {
        if entries.count != used.count { entries = entries.filter { used.contains($0.key) } }
        used.removeAll(keepingCapacity: true)
        budgetLeft = searchBudget
    }

    /// The entry with the new whole lines applied. Nil when the file is not
    /// the one the entry knows: another inode, shorter, other bytes before
    /// the offset, or far longer.
    private static func appended(to known: Entry, signature: FileSignature, handle: FileHandle) -> Entry? {
        guard known.signature.inode == signature.inode, signature.size >= known.offset,
              signature.size - known.offset <= longestAppend else { return nil }
        var entry = known
        guard signature.size > entry.offset else { return entry }
        let start = entry.offset - UInt64(entry.anchor.count)
        guard let data = read(handle, from: start, to: signature.size), data.prefix(entry.anchor.count) == entry.anchor else { return nil }
        guard let end = data.lastIndex(of: newline), end >= data.startIndex + entry.anchor.count else { return entry }
        let whole = data[..<(end + 1)]
        for line in whole.dropFirst(entry.anchor.count).split(separator: newline) {
            switch CodexRolloutReader.record(in: Data(line)) {
            case .context(let cwd)?:
                entry.turn.cwd = cwd ?? entry.turn.cwd
            case .marker(let marker, let turnID, let at)?:
                // A marker settles the state, also when the search behind it is not done.
                entry.turn.note(marker, turnID: turnID, at: at)
                entry.resolved = true
                entry.carry = Data()
                entry.scan = CodexRolloutReader.BackwardScan()
            case nil:
                break
            }
        }
        entry.offset = start + UInt64(whole.count)
        entry.anchor = Data(whole.suffix(anchorLength))
        return entry
    }

    private mutating func search(_ entry: inout Entry, handle: FileHandle) {
        while !entry.resolved {
            let first = entry.searchedFrom == nil
            guard first || budgetLeft > 0 else { return }
            let upper = entry.searchedFrom ?? entry.signature.size
            let step = first ? Self.firstChunk : Self.chunk
            let from = upper > step ? upper - step : 0
            guard var data = Self.read(handle, from: from, to: upper) else { return }
            if !first { budgetLeft -= min(budgetLeft, UInt64(data.count)) }
            if first {
                if let end = data.lastIndex(of: Self.newline) {
                    // A last line that is still being written is left for the next read.
                    data = data[..<(end + 1)]
                    entry.offset = from + UInt64(data.count)
                    entry.anchor = Data(data.suffix(Self.anchorLength))
                } else if from == 0 {
                    data = Data()
                    entry.offset = 0
                } else {
                    entry.anchor = Data(data.suffix(Self.anchorLength))
                }
            }
            if entry.carryDropped {
                // What follows the last line end here is the start of the dropped line.
                if let end = data.lastIndex(of: Self.newline) {
                    data = data[..<(end + 1)]
                    entry.carryDropped = false
                } else {
                    data = Data()
                }
            } else {
                data.append(entry.carry)
            }
            entry.carry = Data()
            var lines = data[...]
            if from > 0 {
                if let end = data.firstIndex(of: Self.newline) {
                    entry.carry = Data(data[..<end])
                    lines = data[(end + 1)...]
                } else {
                    entry.carry = Data(data)
                    lines = Data()[...]
                }
                if entry.carry.count > Self.longestKeptLine {
                    entry.carry = Data()
                    entry.carryDropped = true
                }
            }
            for line in lines.split(separator: Self.newline).reversed() {
                entry.scan.take(Data(line))
                if entry.scan.settled { break }
            }
            entry.searchedFrom = from
            if entry.scan.settled || from == 0 {
                let cwd = entry.turn.cwd ?? entry.scan.turn.cwd
                if entry.scan.turn.lastMarker != nil { entry.turn = entry.scan.turn }
                entry.turn.cwd = cwd
                entry.resolved = true
                entry.carry = Data()
                entry.scan = CodexRolloutReader.BackwardScan()
            }
        }
    }

    /// Nil unless every byte of the range was read.
    private static func read(_ handle: FileHandle, from: UInt64, to: UInt64) -> Data? {
        guard to >= from else { return nil }
        if to == from { return Data() }
        guard (try? handle.seek(toOffset: from)) != nil,
              let data = try? handle.read(upToCount: Int(to - from)), data.count == Int(to - from) else { return nil }
        return data
    }
}
