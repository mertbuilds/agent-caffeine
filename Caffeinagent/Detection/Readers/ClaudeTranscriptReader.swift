import Foundation

/// Fallback for Claude Code versions that write no session state file
/// (before 2.1.119). The transcript is silent for the whole of a tool run or
/// a model answer, and it never shows a permission wait, so it can report
/// only working or idle. Its working is read from the last line, not said
/// by Claude Code, so `VerdictRules` lets it lapse when the file stays
/// unwritten for the activity release time.
struct ClaudeTranscriptReader {
    func report(forTranscript url: URL, now: Date = Date()) -> StateReport? {
        let lastWrite = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Self.report(from: Self.parseTail(of: url), lastWrite: lastWrite, now: now)
    }

    /// Nil when the tail holds no user or assistant turn.
    nonisolated static func report(from parsed: TailParse, lastWrite: Date?, now: Date) -> StateReport? {
        guard let lastTurn = parsed.lastTurn else { return nil }
        let detail: String?
        if parsed.turnInProgress {
            detail = lastTurn == "assistant" ? "running a tool" : "in a turn"
        } else {
            detail = nil
        }
        return StateReport(
            state: parsed.turnInProgress ? .working : .idle,
            since: lastWrite,
            observedAt: now,
            source: .claudeTranscript,
            detail: detail
        )
    }

    struct TailParse {
        var lastTurn: String?
        var turnInProgress = false
    }

    /// Reads the last 16KB of a jsonl. A long last line, such as a big tool
    /// result, can fill that window, so without a turn in it the last 256KB
    /// are read before the session counts as idle.
    nonisolated static func parseTail(of url: URL) -> TailParse {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TailParse() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return TailParse() }
        var result = TailParse()
        for chunk: UInt64 in [16_384, 262_144] {
            let offset = size > chunk ? size - chunk : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(), !data.isEmpty else { return TailParse() }
            result = parseTail(String(decoding: data, as: UTF8.self))
            if result.lastTurn != nil || offset == 0 { break }
        }
        return result
    }

    /// Finds the last user or assistant turn, skipping metadata lines such as
    /// `system` or `last-prompt`, and user lines that Claude Code wrote
    /// itself (`isMeta`). The turn is in progress after a user message or
    /// tool result, and after an assistant line that is not the end of the
    /// answer. An interrupt ends the turn: Claude Code writes it as a user
    /// line, and nothing follows it.
    nonisolated static func parseTail(_ text: String) -> TailParse {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant" else { continue }
            let message = obj["message"] as? [String: Any]
            if type == "assistant" {
                return TailParse(lastTurn: type, turnInProgress: isUnfinished(message))
            }
            if obj["isMeta"] as? Bool == true { continue }
            return TailParse(lastTurn: type, turnInProgress: !isInterrupt(message))
        }
        return TailParse()
    }

    static let interruptMarker = "[Request interrupted by user"

    /// The stop reason is `tool_use` while a tool runs, and missing or null
    /// on a line that was written before the answer ended.
    nonisolated private static func isUnfinished(_ message: [String: Any]?) -> Bool {
        guard let message else { return false }
        if let content = message["content"] as? [[String: Any]], content.contains(where: { $0["type"] as? String == "tool_use" }) { return true }
        guard let reason = message["stop_reason"] as? String else { return true }
        return reason == "tool_use"
    }

    nonisolated private static func isInterrupt(_ message: [String: Any]?) -> Bool {
        if let text = message?["content"] as? String { return text.hasPrefix(interruptMarker) }
        guard let content = message?["content"] as? [[String: Any]] else { return false }
        return content.contains { ($0["text"] as? String)?.hasPrefix(interruptMarker) ?? false }
    }
}
