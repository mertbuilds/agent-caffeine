import Foundation

/// Fallback for Claude Code versions that write no session state file
/// (before 2.1.119). The transcript is silent for the whole of a tool run or
/// a model answer, and it never shows a permission wait, so it can report
/// only working or idle.
struct ClaudeTranscriptReader {
    func report(forTranscript url: URL, now: Date = Date()) -> StateReport? {
        let lastWrite = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return Self.report(from: ClaudeCodeWatcher.parseTail(of: url), lastWrite: lastWrite, now: now)
    }

    /// Nil when the tail holds no user or assistant turn.
    nonisolated static func report(from parsed: ClaudeCodeWatcher.TailParse, lastWrite: Date?, now: Date) -> StateReport? {
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
}
