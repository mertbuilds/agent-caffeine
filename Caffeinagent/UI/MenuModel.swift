import Foundation

/// One line of the agent list in the menu.
struct MenuAgentRow: Equatable, Identifiable {
    enum State: Equatable {
        case working
        case waiting
        case idle
    }

    var id: String
    var title: String
    var state: State
    /// Below the title.
    var detail: String
}

/// Whether the Mac stays awake with the lid closed on battery.
enum LidClosedStatus: Equatable {
    case on
    /// The user switched it off in Preferences.
    case off
    /// The helper is not there, or not allowed yet.
    case notSetUp

    var text: String {
        switch self {
        case .on: return "Lid closed on battery: on"
        case .off: return "Lid closed on battery: off"
        case .notSetUp: return "Lid closed on battery: not set up"
        }
    }
}

/// What the menu shows, worked out from the decision. Pure.
enum MenuModel {
    /// Agents that work come first, then the ones that wait, each on its
    /// own line. Idle sessions of the same agent share one line when there
    /// are two or more, so many open sessions do not fill the menu.
    /// `labels` tells sessions of one agent apart.
    static func rows(for perAgent: [AgentHold], labels: [ProcessIdentity: String] = [:]) -> [MenuAgentRow] {
        let readings = perAgent.map(\.reading)
        var rows: [MenuAgentRow] = []
        for (state, word) in [(WorkState.working, "Working"), (.waitingForUser, "Waits for you")] {
            for reading in readings where reading.verdict.state == state {
                rows.append(MenuAgentRow(
                    id: "\(reading.identity.pid):\(reading.identity.startTime)",
                    title: labels[reading.identity].map { "\(reading.displayName) · \($0)" } ?? reading.displayName,
                    state: state == .working ? .working : .waiting,
                    detail: "\(word) · \(reading.verdict.reason.text)"
                ))
            }
        }
        let idle = readings.filter { $0.verdict.state == .idle }
        var grouped: Set<String> = []
        for reading in idle where grouped.insert(reading.agentID).inserted {
            let count = idle.filter { $0.agentID == reading.agentID }.count
            rows.append(MenuAgentRow(
                id: "idle:\(reading.agentID)",
                title: reading.displayName,
                state: .idle,
                detail: count == 1 ? "Idle · \(reading.verdict.reason.text)" : "\(count) idle sessions"
            ))
        }
        return rows
    }

    /// The folder a session runs in, as its label. Nil for the root folder,
    /// where background services run.
    static func sessionLabel(workingDirectory: String?) -> String? {
        guard let workingDirectory, workingDirectory != "/" else { return nil }
        let name = (workingDirectory as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    static func lidClosedStatus(helper: HelperStatus, wanted: Bool) -> LidClosedStatus {
        guard helper == .enabled else { return .notSetUp }
        return wanted ? .on : .off
    }
}
