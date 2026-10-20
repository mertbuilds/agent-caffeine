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

    /// The line below the menu in Settings, for the mode that is chosen.
    var explanation: String {
        switch self {
        case .always: return "Until you turn Agent Caffeine off."
        case .agentOpen: return "Even when the agent is idle."
        case .agentWorking: return "Your Mac can sleep when every agent is idle."
        }
    }
}
