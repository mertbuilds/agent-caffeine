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

    var explanation: String {
        switch self {
        case .always: return "Always: the Mac stays awake until you switch agent caffeine off, with or without an agent."
        case .agentOpen: return "While an agent is open: the Mac stays awake as long as an agent is running, also when it waits at its prompt."
        case .agentWorking: return "While an agent is working: the Mac stays awake only while an agent does work, and can sleep when every agent is idle."
        }
    }
}
