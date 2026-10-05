import Foundation

/// How the robot at the top of the menu holds itself.
enum HeroPose: Equatable {
    enum SafetyKind: Equatable {
        case battery
        case heat
    }

    /// Keeps the Mac awake. Two wisps of steam, as the icon has them, and
    /// three when three or more agents work.
    case awake(wisps: Int)
    /// Keeps the Mac awake for an agent that waits for the user.
    case attentive
    /// On, and the Mac can sleep.
    case asleep
    /// Switched off, or the license does not allow a hold.
    case off
    /// Stopped to protect the Mac. The robot is knocked out.
    case safetyStop(SafetyKind)
    /// The helper was switched off in Login Items while the sleep flag was
    /// on. The robot is knocked out.
    case helperOff
}

/// Something the user can do from the menu.
enum PanelAction: Equatable {
    case openLoginItems
    case buy
    case enterKey
    case checkLicense
    case activateAgain
    case setUpLidClosed
    case dismissLidClosedHint

    var title: String {
        switch self {
        case .openLoginItems: return "Open System Settings"
        case .buy: return "Buy for $9"
        case .enterKey: return "Enter key…"
        case .checkLicense: return "Check now"
        case .activateAgain: return "Activate again"
        case .setUpLidClosed: return "Set up…"
        case .dismissLidClosedHint: return "Dismiss"
        }
    }
}

/// The one line below the headline that asks for the user's attention.
struct PanelAttention: Equatable {
    /// Most urgent first: the menu shows one at a time.
    enum Kind: Int, Equatable {
        case safetyStop
        case helperSwitchedOff
        case license
        case lidClosedNotSetUp
    }

    var kind: Kind
    var text: String
    var actions: [PanelAction] = []
}

/// One line of the agent list.
struct PanelRow: Equatable, Identifiable {
    enum State: Equatable {
        case working
        case waiting
        case idle
    }

    var id: String
    /// `AgentDefinition.id`, for the logo.
    var agentID: String
    var name: String
    /// The project folder of a session that works or waits.
    var label: String?
    var state: State
    /// "Working", "Running 3 commands", "Idle", "8 idle sessions".
    var status: String
    /// How long the state has lasted, in words. Nil when it is not known
    /// or says nothing.
    var duration: String?
    /// The evidence, for the tooltip.
    var hint: String

    var title: String {
        label.map { "\(name) · \($0)" } ?? name
    }

    /// Below the title for an agent that works or waits, at the trailing
    /// edge for an idle one.
    var detail: String {
        guard let duration else { return status }
        return state == .idle ? "\(status) \(duration)" : "\(status) · \(duration)"
    }

    /// "Claude Code, wiki, working, 12 minutes".
    var accessibilityLabel: String {
        let spoken = status.prefix(1).lowercased() + status.dropFirst()
        return [name, label, spoken, duration].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Everything the menu shows at one moment.
struct PanelState: Equatable {
    var pose: HeroPose
    var title: String
    var subtitle: String
    var attention: PanelAttention?
    /// Always in view: the agents that work, the ones that wait, and the
    /// first idle ones.
    var rows: [PanelRow]
    /// The idle agents behind "9 more idle".
    var moreIdle: [PanelRow] = []
    /// In place of the list when no agent is open.
    var emptyText: String?
    /// License items of the gear menu.
    var licenseActions: [PanelAction] = []

    var moreIdleTitle: String? {
        moreIdle.isEmpty ? nil : "\(moreIdle.count) more idle"
    }

    /// One reading for VoiceOver.
    var headlineAccessibilityLabel: String {
        "\(title), \(subtitle)"
    }
}

/// When each agent instance entered the state it is in now.
struct StateClock: Equatable {
    struct Entry: Equatable {
        var state: WorkState
        var since: Date
    }

    private(set) var entries: [ProcessIdentity: Entry] = [:]

    init() {}

    /// An instance that is not among the readings is gone. One that the
    /// app sees for the first time counts from now: what it did before
    /// is not known.
    func updated(with readings: [AgentReading], now: Date) -> StateClock {
        var next = StateClock()
        for reading in readings {
            if let entry = entries[reading.identity], entry.state == reading.verdict.state {
                next.entries[reading.identity] = entry
            } else {
                next.entries[reading.identity] = Entry(state: reading.verdict.state, since: now)
            }
        }
        return next
    }

    func since(_ identity: ProcessIdentity) -> Date? {
        entries[identity]?.since
    }
}

/// What the menu is worked out from.
struct PanelInput: Equatable {
    var decision: HoldDecision
    var mode: AwakeMode = .agentWorking
    var entitlement: Entitlement = .licensed
    /// Whoever has a key already bought one.
    var hasLicenseKey = false
    /// The project folder of each session that works or waits.
    var labels: [ProcessIdentity: String] = [:]
    var clock = StateClock()
    var settings = DetectionSettings()
    /// The sleep flag is on and the helper was switched off in Login Items.
    var flagLeftOn = false
    /// A Mac with a battery whose helper is not allowed yet, while the
    /// setting asks for it.
    var lidClosedNeedsSetup = false
    var lidClosedHintDismissed = false
}
