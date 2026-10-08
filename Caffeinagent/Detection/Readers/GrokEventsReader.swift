import Foundation

/// What the event log of one Grok Build session says about its newest turn.
struct GrokTurnState: Equatable {
    enum Turn: Equatable {
        /// `since` is nil when the start of the turn is not in the part
        /// of the file that was read.
        case running(since: Date?)
        case ended(at: Date?)
    }

    /// Nil when no turn marker was found.
    var turn: Turn?
    /// When the newest permission request with no answer was written.
    /// Only for a turn that runs.
    var askedAt: Date?
}

struct GrokSessionLog: Equatable {
    var url: URL
    /// The name of the session's folder.
    var sessionID: String
}

/// Reads `~/.grok/sessions/<encoded cwd>/<session id>/events.jsonl`, the
/// event log Grok Build writes per session (docs/research/10-grok-build.md).
/// One line per event, each with `ts` and `type`:
///
///     {"ts":"...","type":"turn_started","session_id":"...","turn_number":0,...}
///     {"ts":"...","type":"permission_requested","tool_name":"read_file"}
///     {"ts":"...","type":"permission_resolved","tool_name":"read_file","decision":"allow","wait_ms":3094}
///     {"ts":"...","type":"turn_ended","outcome":"completed"}
///
/// A turn is in progress when the newest of `turn_started` and
/// `turn_ended` is the start. In the measured log no line of a turn came
/// after its `turn_ended`. The lines hold no text of the user or of the
/// model, and only `type` and `ts` are read.
///
/// The log carries no pid. The caller ties it to a process by the working
/// directory, and counts a file only when it was written after the
/// process started: a killed Grok Build leaves a turn that never ends.
struct GrokEventsReader {
    var sessionsDirectory: URL

    static let fileName = "events.jsonl"

    init(sessionsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/sessions")) {
        self.sessionsDirectory = sessionsDirectory
    }

    /// The logs of the sessions of one working directory. Grok Build
    /// names the group folder after the directory, URL-encoded
    /// (`%2FUsers%2Fme%2Fproject`). The name is decoded here and not
    /// built, so it does not matter which characters Grok Build encodes.
    /// A directory whose encoded name is longer than 255 bytes gets
    /// another name and is not found.
    func logs(forDirectory directory: String) -> [GrokSessionLog] {
        let manager = FileManager.default
        let wanted = Self.resolved(directory)
        var logs: [GrokSessionLog] = []
        for group in (try? manager.contentsOfDirectory(atPath: sessionsDirectory.path)) ?? [] {
            guard let decoded = group.removingPercentEncoding, decoded.hasPrefix("/"), Self.resolved(decoded) == wanted else { continue }
            let folder = sessionsDirectory.appendingPathComponent(group)
            for session in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where !session.hasPrefix(".") {
                let url = folder.appendingPathComponent(session).appendingPathComponent(Self.fileName)
                if FileSignature(path: url.path) != nil { logs.append(GrokSessionLog(url: url, sessionID: session)) }
            }
        }
        return logs
    }

    /// `/tmp` and `/private/tmp` are the same directory.
    nonisolated static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: Parsing

    /// Grok Build writes a `phase_changed` line for each piece of the
    /// answer, so a long turn puts its start far from the end of the
    /// file. The tail is read in steps until a turn marker is in it.
    static let tailSteps: [UInt64] = [65_536, 1_048_576, 8 * 1_048_576]

    nonisolated static func parseTail(of url: URL) -> GrokTurnState {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return GrokTurnState() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return GrokTurnState() }
        for step in tailSteps {
            let offset = size > step ? size - step : 0
            guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return GrokTurnState() }
            let state = parseTail(data, fromStart: offset == 0)
            if state.turn != nil || offset == 0 { return state }
        }
        return GrokTurnState()
    }

    nonisolated static func parseTail(_ text: String) -> GrokTurnState {
        parseTail(Data(text.utf8), fromStart: true)
    }

    private enum Kind {
        case started, ended, asked, answered
    }

    private static let kinds: [(name: String, bytes: Data, kind: Kind)] = {
        let named: [(String, Kind)] = [("turn_started", .started), ("turn_ended", .ended), ("permission_requested", .asked), ("permission_resolved", .answered)]
        return named.map { ($0.0, Data($0.0.utf8), $0.1) }
    }()

    /// The newest turn marker decides. A request counts as open when no
    /// answer follows it in the same turn. A last line that is cut off in
    /// the middle of a write is passed over. `fromStart` is false when
    /// the data begins inside a line.
    nonisolated static func parseTail(_ data: Data, fromStart: Bool) -> GrokTurnState {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)[...]
        if !fromStart { lines = lines.dropFirst() }
        var answers = 0
        var askedAt: Date?
        var asked = false
        for line in lines.reversed() where !line.isEmpty {
            guard let (kind, at) = record(in: line) else { continue }
            switch kind {
            case .started: return GrokTurnState(turn: .running(since: at), askedAt: askedAt)
            case .ended: return GrokTurnState(turn: .ended(at: at))
            case .answered: answers += 1
            case .asked:
                if answers > 0 {
                    answers -= 1
                } else if !asked {
                    asked = true
                    askedAt = at
                }
            }
        }
        return GrokTurnState()
    }

    /// Most lines are `phase_changed`. Only a line that holds the name of
    /// a marker is parsed.
    nonisolated private static func record(in line: Data) -> (kind: Kind, at: Date?)? {
        guard kinds.contains(where: { line.range(of: $0.bytes) != nil }),
              let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String, let kind = kinds.first(where: { $0.name == type })?.kind else { return nil }
        return (kind, ReportedTime.date(record["ts"]))
    }
}

/// What the logs of one Grok Build process say together.
enum GrokSummary {
    /// Grok Build writes `permission_requested` for every tool call, also
    /// when it decides by itself. In the measured log all 72 requests
    /// got their answer after 2.4 to 12.6 seconds, with the permission
    /// mode `auto`. So a request is a wait for the user only when it is
    /// open for longer than this.
    static let askSettle: TimeInterval = 15

    /// `readings` are the logs that were written since the process
    /// started. Working while any session is in a turn, then waiting, and
    /// idle only when every log was understood. Nil with no log.
    static func report(of readings: [GrokTurnState], now: Date, settle: TimeInterval = askSettle) -> StateReport? {
        var workingSince: Date?
        var working = false
        var waitingSince: Date?
        var newestEnd: Date?
        var unknown = false
        for reading in readings {
            switch reading.turn {
            case nil:
                unknown = true
            case .running(let since):
                if let asked = reading.askedAt, asked <= now, now.timeIntervalSince(asked) >= settle {
                    waitingSince = max(waitingSince ?? asked, asked)
                } else {
                    working = true
                    if let since { workingSince = min(workingSince ?? since, since) }
                }
            case .ended(let at):
                if let at { newestEnd = max(newestEnd ?? at, at) }
            }
        }
        if working {
            return StateReport(state: .working, since: workingSince, observedAt: now, source: .grokEvents, detail: "in a turn")
        }
        if let waitingSince {
            return StateReport(state: .waitingForUser, since: waitingSince, observedAt: now, source: .grokEvents, detail: nil)
        }
        guard !readings.isEmpty, !unknown else { return nil }
        return StateReport(state: .idle, since: newestEnd, observedAt: now, source: .grokEvents, detail: nil)
    }
}
