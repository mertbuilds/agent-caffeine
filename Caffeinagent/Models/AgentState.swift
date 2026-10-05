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

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .waitingForInput: return "Waiting for input"
        case .active: return "Active"
        }
    }
}

enum AwakeMode: String, CaseIterable, Identifiable {
    case always
    case agentOpen
    case agentWorking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always"
        case .agentOpen: return "While an agent is open"
        case .agentWorking: return "While an agent is working"
        }
    }

    var explanation: String {
        switch self {
        case .always: return "Always: the Mac stays awake until you switch agent caffeine off. It also stays awake with the lid closed, on battery too when the battery override is installed."
        case .agentOpen: return "While an agent is open: the Mac stays awake as long as an agent is running, also when it waits at its prompt."
        case .agentWorking: return "While an agent is working: the Mac stays awake only while an agent does work, and can sleep when every agent is idle."
        }
    }

    func shouldHold(enabled: Bool, agents: [DetectedAgent]) -> Bool {
        guard enabled else { return false }
        switch self {
        case .always: return true
        case .agentOpen: return !agents.isEmpty
        case .agentWorking: return agents.contains { $0.state == .active }
        }
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
