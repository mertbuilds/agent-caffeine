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
    /// Keeps the Mac awake so it stays reachable, with no agent at work.
    /// Calm: one wisp of steam, and a light that does not breathe.
    case reachable
    /// Keeps the Mac awake for an agent that waits for the user.
    case attentive
    /// On, and the Mac can sleep.
    case asleep
    /// Switched off, or the license does not allow a hold.
    case off
    /// Paused by the user. Drawn like `asleep`: it starts again by itself,
    /// so the grey of `off` would be wrong.
    case paused
    /// Stopped to protect the Mac. The robot is knocked out.
    case safetyStop(SafetyKind)
    /// The helper was switched off in Login Items while the sleep flag was
    /// on. The robot is knocked out.
    case helperOff
}

/// Something the user can do from the menu.
enum PanelAction: Equatable {
    case openLoginItems
    case tryHelperAgain
    case buy
    case enterKey
    case checkLicense
    case activateAgain
    case setUpLidClosed
    case dismissLidClosedHint
    case pause(PauseChoice)
    case resume
    case stayReachable(ReachableChoice)
    case stopReachable
    /// Opens the settings where a tool that is not in the list is added.
    case agentNotListed
    /// From the menu of a row: the rule of one agent. `.automatic` takes
    /// the rule away.
    case setAgentRule(agentID: String, rule: AgentRule)
    case openAgentSettings
    /// From a click on the line of one agent: brings the app it runs in
    /// to the front.
    case goToAgent(ProcessIdentity, app: String)
    /// From the line of a hold from the command line: ends that hold.
    case stopHold(id: String)
    /// From the line of a job hold of "Wake for jobs": ends that hold.
    case stopJobHold(id: String)
    case dismissSleepNote
    case openHelp

    var title: String { PanelText.title(of: self) }
}

/// The one line below the headline that asks for the user's attention.
struct PanelAttention: Equatable {
    /// Most urgent first: the menu shows one at a time.
    enum Kind: Int, Equatable {
        case safetyStop
        case helperSwitchedOff
        case helperNotResponding
        case helperLost
        /// The closed lid limit let go of the agents. See `AgentStop`.
        case closedLidLimit
        /// The Mac is offline, so agents do not keep it awake, while
        /// something else does.
        case agentsOffline
        case license
        /// "Stay reachable" is on, and a closed lid on battery still
        /// puts the Mac to sleep.
        case reachableNeedsLidClosed
        case lidClosedNotSetUp
        /// Why the Mac slept while an agent worked or waited. A line of
        /// its own, above the one that asks for attention.
        case sleptAnyway
    }

    var kind: Kind
    var text: String
    var actions: [PanelAction] = []
}

/// The charge of the battery and the level where Agent Caffeine lets the
/// Mac sleep, on one line below the headline. Only while the Mac runs on battery and Agent Caffeine
/// could keep it awake.
struct PanelBattery: Equatable {
    enum Level: Equatable {
        case normal
        /// Within `MenuModel.batteryWarningPoints` of the floor, or low with
        /// no floor.
        case nearFloor
        /// The battery floor stopped Agent Caffeine.
        case stopped
        /// With no floor, close to empty. See `NoLimitBatteryWarning.levels`.
        case nearEmpty
    }

    /// 0 to 100.
    var percent: Int
    /// The battery limit. Nil when it is off.
    var floor: Int?
    var level: Level

    /// What the mark and the number are drawn in. The rest of the line
    /// stays quiet.
    enum Tone: Equatable {
        case quiet
        case amber
        case red
    }

    /// How much of the mark is filled, 0 to 1.
    var fill: Double { Double(percent) / 100 }
    var tone: Tone {
        switch level {
        case .normal: return .quiet
        case .nearFloor: return .amber
        case .stopped, .nearEmpty: return .red
        }
    }
    /// "88%". Nil while the floor stopped Agent Caffeine: the headline
    /// says the number then.
    var charge: String? { level == .stopped ? nil : PanelText.percent(percent) }
    /// What follows from it, after the number.
    var consequence: String {
        guard let floor else { return PanelText.batteryNoLimit }
        return level == .stopped
            ? PanelText.batteryStartsAgain(atPercent: floor + SafetyMonitor.batteryRecoveryPoints)
            : PanelText.batterySleepsAt(percent: floor)
    }
    /// One reading for VoiceOver.
    var accessibilityLabel: String {
        guard let floor else { return PanelText.batterySpokenNoLimit(percent: percent) }
        return level == .stopped
            ? PanelText.batterySpokenStopped(percent: percent, recovery: floor + SafetyMonitor.batteryRecoveryPoints)
            : PanelText.batterySpoken(percent: percent, floor: floor)
    }
}

/// The header line of a group of the agent list.
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
    /// What tells this line from another one with the same name and
    /// folder: the session's name, its terminal, or when it started.
    var distinction: String?
    var state: State
    /// A whole phrase: "Working for 14 minutes", "Idle for 6 hours",
    /// "3 working". Below the title for one session that works or waits,
    /// at the trailing edge for an idle one and for several sessions.
    var detail: String
    /// The evidence, for the tooltip.
    var hint: String
    /// What a click on the line does. Nil for a line that stands for
    /// several sessions, and for a session with no app to go to.
    var goTo: PanelAction?

    /// A title up to this long fits the menu on one line.
    static let titleFit = 36

    /// "Claude Code · blog". With a distinction the agent's name gives
    /// way when the line would not fit, because the mark already shows
    /// the agent: "blog · sidebar-layout-spacing".
    var title: String {
        let full = ([name] + place).joined(separator: " · ")
        guard distinction != nil, full.count > Self.titleFit else { return full }
        return place.joined(separator: " · ")
    }

    /// The folder and the distinction. A session name that begins with
    /// the folder says both: "blog-1d".
    private var place: [String] {
        guard let distinction else { return label.map { [$0] } ?? [] }
        guard let label else { return [distinction] }
        let rest = distinction.lowercased().hasPrefix(label.lowercased()) ? distinction.dropFirst(label.count) : nil
        // "blog-1d" in the folder "blog", and not "about" in the folder "a".
        if let rest, rest.first.map({ !$0.isLetter && !$0.isNumber }) ?? true { return [distinction] }
        return [label, distinction]
    }

    /// "Claude Code, blog, working for 12 minutes".
    var accessibilityLabel: String {
        let spoken = detail.prefix(1).lowercased() + detail.dropFirst()
        return ([name] + place + [spoken]).joined(separator: ", ")
    }
}

/// One session below the name of its agent, or one line that counts the
/// sessions that are not listed.
struct PanelChild: Equatable, Identifiable {
    var id: String
    /// The session's name, else its folder, else its terminal, else when
    /// it started. Or the count: "8 idle sessions", "and 4 more".
    var label: String
    /// A whole phrase: "Working for 6 minutes". Nil for a count.
    var detail: String?
    /// The folder and the evidence, for the tooltip.
    var hint: String
    /// What a click on the line does. Nil for a count, and for a session
    /// with no app to go to.
    var goTo: PanelAction?

    /// "blog-6e, working for 6 minutes".
    var accessibilityLabel: String {
        guard let detail else { return label }
        return "\(label), \(detail.prefix(1).lowercased() + detail.dropFirst())"
    }
}

/// All sessions of one agent: a header line, and the sessions below it
/// when there are two or more.
struct PanelGroup: Equatable, Identifiable {
    /// What decides whether the group is open before the user chose.
    enum Kind: Equatable {
        /// A session works or waits.
        case active
        case idle
    }

    /// With one session this is the session's own line. With more, the
    /// name alone, the most urgent state inside for the ring, and the
    /// summary as its detail: "3 working".
    var header: PanelRow
    /// Below the header of an open group. Empty when there is nothing to
    /// open: one session, or an agent that a rule ignores.
    var children: [PanelChild] = []
    var working = 0
    var waiting = 0
    var idle = 0
    /// What the user set for this agent, for the menu of the row.
    var rule = AgentRule.automatic
    /// Only on the line of a hold from the command line and of a job
    /// hold: the way to end it. Such a line has no rule and no sessions.
    var stop: PanelAction?

    /// `AgentDefinition.id`: the group keeps its place when its sessions
    /// change state.
    var id: String { header.agentID }
    var kind: Kind { working + waiting > 0 ? .active : .idle }
    var canToggle: Bool { !children.isEmpty }
    var opensByDefault: Bool { kind == .active }

    /// "Claude Code, 3 working, 8 idle".
    var accessibilityLabel: String {
        canToggle ? "\(header.name), \(PanelText.groupSpoken(working: working, waiting: waiting, idle: idle))" : header.accessibilityLabel
    }
}

/// Which groups the user opened or closed by hand. A choice holds while
/// the group stays of the same kind.
struct GroupDisclosure: Equatable {
    private struct Choice: Equatable {
        var isOpen: Bool
        var kind: PanelGroup.Kind
    }

    private var choices: [String: Choice] = [:]

    init() {}

    func isOpen(_ group: PanelGroup) -> Bool {
        guard group.canToggle else { return false }
        guard let choice = choices[group.id], choice.kind == group.kind else { return group.opensByDefault }
        return choice.isOpen
    }

    mutating func toggle(_ group: PanelGroup) {
        guard group.canToggle else { return }
        choices[group.id] = Choice(isOpen: !isOpen(group), kind: group.kind)
    }

    /// Without the choices for a group that is gone or changed its kind,
    /// so an old choice never comes back.
    func settled(with groups: [PanelGroup]) -> GroupDisclosure {
        let kinds = Dictionary(groups.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        var next = self
        next.choices = choices.filter { kinds[$0.key] == $0.value.kind }
        return next
    }
}

/// Everything the menu shows at one moment.
struct PanelState: Equatable {
    var pose: HeroPose
    var title: String
    var subtitle: String
    var attention: PanelAttention?
    /// Why the Mac slept while an agent worked or waited, until the user
    /// dismisses it.
    var sleepNote: PanelAttention?
    /// Nil on wall power, on a Mac without a battery, and while agent
    /// caffeine is off, paused or without a license.
    var battery: PanelBattery?
    /// "Wakes at 09:14 for backup", while a wake alarm of "Wake for
    /// jobs" is set. Nil when none is.
    var wakeLine: String?
    /// "On your iPhone hotspot since 14:02", while the Mac is on the
    /// hotspot because Wi-Fi was lost. Nil when it is not.
    var hotspotLine: String?
    /// Always in view: the agents with a session that waits or works, and
    /// the first idle ones.
    var groups: [PanelGroup]
    /// The idle agents behind "3 more idle agents".
    var moreIdle: [PanelGroup] = []
    /// In place of the list when no agent is open.
    var emptyText: String?
    /// A link below `emptyText`.
    var emptyAction: PanelAction?
    /// License items of the gear menu.
    var licenseActions: [PanelAction] = []
    /// "Paused until 15:30" for the bar at the bottom. Nil when not paused.
    var pausedLabel: String?
    /// "Reachable until 18:30" for the bar at the bottom. Nil when not on.
    var reachableLabel: String?
    /// The choices of "stay reachable". Empty while Agent Caffeine may
    /// not keep the Mac awake.
    var reachableActions: [PanelAction] = []
    /// What "stay reachable" costs, below its choices. Only on battery.
    var reachableCost: String?
    /// For the item in the menu bar, when it says more than the pose.
    var menuBarAccessibilityLabel: String?

    var moreIdleTitle: String? {
        moreIdle.isEmpty ? nil : PanelText.moreIdle(moreIdle.count)
    }

    /// One reading for VoiceOver.
    var headlineAccessibilityLabel: String {
        "\(title), \(subtitle)"
    }
}

/// What the bar at the bottom shows. Nothing in it follows the time or
/// what the agents do, so the bar and its menus stay as they are while
/// the rest of the menu counts on.
struct PanelBar: Equatable {
    /// The switch.
    var enabled = true
    var mode = AwakeMode.agentWorking
    /// "Paused until 15:30". Nil when not paused.
    var pausedLabel: String?
    /// "Reachable until 18:30". Nil when not on.
    var reachableLabel: String?
    /// The choices of "stay reachable". Empty while Agent Caffeine may
    /// not keep the Mac awake.
    var reachableActions: [PanelAction] = []
    /// What "stay reachable" costs, below its choices. Only on battery.
    var reachableCost: String?
    /// License items of the gear menu.
    var licenseActions: [PanelAction] = []
}

extension PanelBar {
    /// The bar of a state, for a menu that is drawn from one.
    init(_ state: PanelState, enabled: Bool, mode: AwakeMode) {
        self.init(
            enabled: enabled, mode: mode, pausedLabel: state.pausedLabel, reachableLabel: state.reachableLabel,
            reachableActions: state.reachableActions, reachableCost: state.reachableCost, licenseActions: state.licenseActions
        )
    }
}

/// When each agent instance entered the state it is in now.
struct StateClock: Equatable {
    struct Entry: Equatable {
        var state: WorkState
        var since: Date
        /// The state it left. Nil when the app first saw it in this one,
        /// so `since` is not when the state began.
        var before: WorkState?
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
                next.entries[reading.identity] = Entry(state: reading.verdict.state, since: now, before: entries[reading.identity]?.state)
            }
        }
        return next
    }

    func since(_ identity: ProcessIdentity) -> Date? {
        entries[identity]?.since
    }

    func before(_ identity: ProcessIdentity) -> WorkState? {
        entries[identity]?.before
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
    /// What tells sessions with the same name and folder apart.
    var hints: [ProcessIdentity: SessionHint] = [:]
    /// The name of the app each session is shown in, where there is one.
    var hosts: [ProcessIdentity: String] = [:]
    /// For the start time of a session, when nothing else tells it apart.
    var calendar = Calendar.current
    /// For the time a pause ends at, with the user's 12 or 24 hour clock.
    var locale = Locale.current
    /// Nil when the user did not pause.
    var pausedUntil: Date?
    var clock = StateClock()
    var settings = DetectionSettings()
    /// The sleep flag is on and the helper was switched off in Login Items.
    var flagLeftOn = false
    /// A Mac with a battery whose helper is not allowed yet, while the
    /// setting asks for it.
    var lidClosedNeedsSetup = false
    /// The helper is allowed and gives no answer, while the setting asks
    /// for it on a Mac with a battery.
    var helperNotResponding = false
    /// The helper was registered again and still gives no answer.
    var helperRepairTried = false
    /// The helper was set up before and is gone, while the setting asks
    /// for it on a Mac with a battery.
    var helperLost = false
    var lidClosedHintDismissed = false
    /// Nil when the user did not ask the Mac to stay reachable.
    var reachableUntil: Date?
    /// The switch. A pause does not change it.
    var enabled = true
    var onBattery = false
    /// The lid, the sleep flag and what macOS does about sleep, for the
    /// line of an agent that waits.
    var macSleep = MacSleepState()
    /// Nil on a Mac without a battery.
    var batteryPercent: Int?
    /// Nil when the Mac did not sleep under an agent, or the user
    /// dismissed the line.
    var sleepNote: SleepNote?
    /// The wake alarm of "Wake for jobs" that is set.
    var wakeAlarm: JobAlarm?
    /// `HotspotView.onHotspotSince`.
    var hotspotSince: Date?
}
