import Foundation

enum AgentState: String, Comparable {
    case idle
    case waitingForInput
    case active

    private var rank: Int {
        switch self {
        case .idle: return 0
        case .waitingForInput: return 1
        case .active: return 2
        }
    }

    static func < (lhs: AgentState, rhs: AgentState) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct DetectedAgent: Identifiable, Equatable {
    enum Source: String {
        case claudeCode = "Claude Code"
        case process = "CLI"
    }

    let id: String
    let source: Source
    let label: String
    let state: AgentState
    let lastActivity: Date
}
