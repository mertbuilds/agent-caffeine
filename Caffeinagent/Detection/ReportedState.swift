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
    /// The turn is over and work it left behind still runs: Claude Code's
    /// `shell`. The state is working, and the agent has answered.
    var turnEnded = false
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
