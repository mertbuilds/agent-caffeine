import Foundation

/// What an agent says about itself, or what its session log proves.
enum ReportedState: Equatable {
    /// A turn or tool is in progress.
    case working
    /// Blocked on a permission prompt or a question.
    case waitingForUser
    /// At its prompt, nothing in progress.
    case idle
}

struct StateReport: Equatable {
    enum Source: Equatable {
        case claudeSessionFile
        case claudeJobState
        case claudeTranscript
        case codexRollout
        case cursorTranscript
        case grokEvents
        case hermesState
        case openClawState
        case fileActivity
    }

    var state: ReportedState
    /// When this state began, if the source says.
    var since: Date?
    /// When we read it.
    var observedAt: Date
    var source: Source
    /// Short, user-safe reason fragment such as "running a tool". Never user content.
    var detail: String?
    /// Idle only: the turn is over, and the agent says that background
    /// commands of the session still run: Claude Code's `shell`. That
    /// word has no end of its own: a dev server that was left running
    /// keeps it for as long as the session lives. So it is no working,
    /// and `VerdictRules` holds for it only while the commands show work.
    var backgroundWork = false
    /// Idle only: the turn ended with an error. The error text is never
    /// read: it can hold account details.
    var failed = false
}

/// Timestamps as the agents write them: epoch milliseconds (Claude session
/// files), epoch seconds (Codex `started_at`) or ISO 8601 with or without
/// fractional seconds (Claude job state, Codex record `timestamp`).
enum ReportedTime {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return fractional.date(from: text) ?? plain.date(from: text)
        }
        guard let number = value as? Double, number.isFinite, number > 0 else { return nil }
        // Epoch seconds stay under 1e11 until the year 5138.
        return Date(timeIntervalSince1970: number >= 1e11 ? number / 1000 : number)
    }
}
