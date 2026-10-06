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
    /// While agent caffeine keeps the Mac awake with the lid closed, the
    /// built-in display is kept dark. See `DisplayRules`.
    var displayOffLidClosed = true
    /// On a Mac with a lid angle sensor, the built-in display gets darker
    /// from 45 degrees on, and brighter again the same way. See
    /// `LidDimming`.
    var dimAsLidCloses = true
    /// On power, the Mac stays awake while a tool's phone access is on,
    /// also with no agent at work.
    var stayAwakeForRemoteAccess = true
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
        case batteryFloorPercent, stayAwakeLidClosedOnBattery, displayOffLidClosed, dimAsLidCloses, stayAwakeForRemoteAccess, agentRules, userAgentNames
    }

    /// No time is shorter than a second or longer than a day.
    static let timeRange: ClosedRange<TimeInterval> = 1...86_400
    static let batteryFloorRange = 5...50

    /// A key that is missing keeps its default, so settings saved by an
    /// older build still load. The numbers are not trusted: a time that is
    /// no time (below a second, or not finite) falls back to its default,
    /// one that is too long is cut, and the battery floor stays in the
    /// range the Preferences offer. A zero release time would drop the hold
    /// between two tool calls, and a floor of 0 would never stop.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DetectionSettings()
        func time(_ key: CodingKeys, _ fallback: TimeInterval) throws -> TimeInterval {
            guard let value = try container.decodeIfPresent(TimeInterval.self, forKey: key),
                  value.isFinite, value >= Self.timeRange.lowerBound else { return fallback }
            return min(value, Self.timeRange.upperBound)
        }
        releaseAfterState = try time(.releaseAfterState, defaults.releaseAfterState)
        releaseAfterActivity = try time(.releaseAfterActivity, defaults.releaseAfterActivity)
        waitingHold = try time(.waitingHold, defaults.waitingHold)
        weakEvidenceCap = try time(.weakEvidenceCap, defaults.weakEvidenceCap)
        let floor = try container.decodeIfPresent(Int.self, forKey: .batteryFloorPercent) ?? defaults.batteryFloorPercent
        batteryFloorPercent = min(max(floor, Self.batteryFloorRange.lowerBound), Self.batteryFloorRange.upperBound)
        stayAwakeLidClosedOnBattery = try container.decodeIfPresent(Bool.self, forKey: .stayAwakeLidClosedOnBattery) ?? defaults.stayAwakeLidClosedOnBattery
        displayOffLidClosed = try container.decodeIfPresent(Bool.self, forKey: .displayOffLidClosed) ?? defaults.displayOffLidClosed
        dimAsLidCloses = try container.decodeIfPresent(Bool.self, forKey: .dimAsLidCloses) ?? defaults.dimAsLidCloses
        stayAwakeForRemoteAccess = try container.decodeIfPresent(Bool.self, forKey: .stayAwakeForRemoteAccess) ?? defaults.stayAwakeForRemoteAccess
        agentRules = try container.decodeIfPresent([String: AgentRule].self, forKey: .agentRules) ?? defaults.agentRules
        userAgentNames = try container.decodeIfPresent([String].self, forKey: .userAgentNames) ?? defaults.userAgentNames
    }
}
