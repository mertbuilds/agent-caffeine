import Foundation

/// How the user wants one agent to be judged.
enum AgentRule: String, Codable, CaseIterable {
    /// Judged by its evidence.
    case automatic
    /// Counts as working for as long as it is open.
    case alwaysWorkingWhileOpen
    /// Never keeps the Mac awake.
    case ignore
}

struct DetectionSettings: Codable, Equatable {
    /// How long the Mac stays awake after an agent that reports its own
    /// state goes idle.
    var releaseAfterState: TimeInterval = 120
    /// How long an agent that is judged by its activity counts as working
    /// after its last sign of work.
    var releaseAfterActivity: TimeInterval = 300
    /// How long the Mac stays awake for an agent that waits for the user.
    var waitingHold: TimeInterval = 300
    /// The longest time CPU use alone, with no clear sign of work, can count
    /// as working.
    var weakEvidenceCap: TimeInterval = 1800
    var batteryFloorPercent = SafetyMonitor.defaultBatteryFloorPercent
    var stayAwakeLidClosedOnBattery = true
    /// By `AgentDefinition.id`. An agent with no entry is `.automatic`.
    var agentRules: [String: AgentRule] = [:]
    /// Process names the user added, matched at the generic level.
    var userAgentNames: [String] = []

    init() {}

    func rule(for agentID: String) -> AgentRule {
        agentRules[agentID] ?? .automatic
    }

    private enum CodingKeys: String, CodingKey {
        case releaseAfterState, releaseAfterActivity, waitingHold, weakEvidenceCap
        case batteryFloorPercent, stayAwakeLidClosedOnBattery, agentRules, userAgentNames
    }

    /// A key that is missing keeps its default, so settings saved by an
    /// older build still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DetectionSettings()
        releaseAfterState = try container.decodeIfPresent(TimeInterval.self, forKey: .releaseAfterState) ?? defaults.releaseAfterState
        releaseAfterActivity = try container.decodeIfPresent(TimeInterval.self, forKey: .releaseAfterActivity) ?? defaults.releaseAfterActivity
        waitingHold = try container.decodeIfPresent(TimeInterval.self, forKey: .waitingHold) ?? defaults.waitingHold
        weakEvidenceCap = try container.decodeIfPresent(TimeInterval.self, forKey: .weakEvidenceCap) ?? defaults.weakEvidenceCap
        batteryFloorPercent = try container.decodeIfPresent(Int.self, forKey: .batteryFloorPercent) ?? defaults.batteryFloorPercent
        stayAwakeLidClosedOnBattery = try container.decodeIfPresent(Bool.self, forKey: .stayAwakeLidClosedOnBattery) ?? defaults.stayAwakeLidClosedOnBattery
        agentRules = try container.decodeIfPresent([String: AgentRule].self, forKey: .agentRules) ?? defaults.agentRules
        userAgentNames = try container.decodeIfPresent([String].self, forKey: .userAgentNames) ?? defaults.userAgentNames
    }
}
