import Foundation

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

    /// For the bar at the bottom of the menu.
    var shortTitle: String {
        switch self {
        case .always: return "Always"
        case .agentOpen: return "While open"
        case .agentWorking: return "While working"
        }
    }

    var explanation: String {
        switch self {
        case .always: return "Always: your Mac stays awake until you turn Agent Caffeine off, even when no agent is open."
        case .agentOpen: return "While an agent is open: your Mac stays awake as long as an agent is open, even when it is idle."
        case .agentWorking: return "While an agent is working: your Mac stays awake only while an agent is working, and can sleep when every agent is idle."
        }
    }
}
