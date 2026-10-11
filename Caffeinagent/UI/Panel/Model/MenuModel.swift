import Foundation

/// What the menu shows, worked out from the decision. Pure: the caller
/// passes the time.
enum MenuModel {
    /// Idle agents in view before the rest goes behind "more idle agents".
    static let idleGroupsInView = 4
    /// Idle sessions that an opened group lists before "and 4 more".
    static let idleChildrenInView = 6
    /// The trial is named in the menu from this many days left.
    static let trialWarningDays = 2
    /// The line of the battery turns amber this many points above the floor.
    static let batteryWarningPoints = 10

    static func state(_ input: PanelInput, now: Date) -> PanelState {
        let pose = pose(input)
        // The sleep flag is on with no helper to clear it, whatever the
        // decision says.
        let (title, subtitle) = pose == .helperOff
            ? (PanelText.helperOffTitle, PanelText.helperOffReason)
            : PanelText.headline(
                input.decision.headline, outlook: SleepOutlook(input.decision, mac: input.macSleep, now: now),
                now: now, calendar: input.calendar, locale: input.locale
            )
        let (groups, moreIdle) = groups(input, now: now)
        let bar = bar(input)
        // Only then a new agent is all that is missing.
        let invites = input.decision.headline == .noAgents && pose != .helperOff
        let isEmpty = input.decision.perAgent.isEmpty && input.decision.manualHolds.isEmpty && input.decision.jobHolds.isEmpty
        return PanelState(
            pose: pose,
            title: title,
            subtitle: subtitle,
            attention: attention(input),
            sleepNote: sleepNote(input),
            battery: battery(input),
            wakeLine: wakeLine(input, now: now),
            groups: groups,
            moreIdle: moreIdle,
            emptyText: isEmpty ? PanelText.empty(invites: invites) : nil,
            emptyAction: isEmpty && invites ? .agentNotListed : nil,
            licenseActions: bar.licenseActions,
            pausedLabel: bar.pausedLabel,
            reachableLabel: bar.reachableLabel,
            reachableActions: bar.reachableActions,
            reachableCost: bar.reachableCost,
            menuBarAccessibilityLabel: menuBarAccessibilityLabel(input)
        )
    }

    // MARK: Bar

    /// The bar at the bottom. It takes no time: the end of a pause is a
    /// time of day, which changes only when the pause does.
    static func bar(_ input: PanelInput) -> PanelBar {
        PanelBar(
            enabled: input.enabled,
            mode: input.mode,
            pausedLabel: input.pausedUntil.map { PanelText.pausedUntil($0, calendar: input.calendar, locale: input.locale) },
            reachableLabel: reachableLabel(input),
            reachableActions: canStayReachable(input) ? ReachableChoice.allCases.map(PanelAction.stayReachable) : [],
            reachableCost: input.onBattery && input.batteryPercent != nil ? PanelText.reachableCost : nil,
            licenseActions: licenseActions(input)
        )
    }

    // MARK: Hero

    /// A safety stop comes first, like its line below the headline. Then
    /// the helper that was switched off, whatever the headline says.
    static func pose(_ input: PanelInput) -> HeroPose {
        let pose = pose(for: input.decision.headline)
        if case .safetyStop = pose { return pose }
        return input.flagLeftOn ? .helperOff : pose
    }

    static func pose(for headline: HoldHeadline) -> HeroPose {
        switch headline {
        case .working(.many(let count)) where count >= 3: return .awake(wisps: 3)
        case .working, .finishedRecently, .open, .alwaysOn, .remoteAccess, .manualHold, .scheduledJob: return .awake(wisps: 2)
        case .reachable: return .reachable
        case .waitingHeld: return .attentive
        case .idle, .waitingReleased, .noAgents: return .asleep
        case .safetyStop(.batteryLow), .safetyStop(.weakCharger), .safetyStop(.closedLid): return .safetyStop(.battery)
        case .safetyStop(.tooHot): return .safetyStop(.heat)
        case .switchedOff, .notEntitled: return .off
        case .paused: return .paused
        }
    }

    // MARK: Stay reachable

    /// The time counts while it holds nothing too, as behind a pause it
    /// could not be. Not after a stop: the switch and a safety stop end it.
    private static func reachableLabel(_ input: PanelInput) -> String? {
        guard input.pausedUntil == nil else { return nil }
        return input.reachableUntil.map { PanelText.reachableUntil($0, calendar: input.calendar, locale: input.locale) }
    }

    /// Offered while Agent Caffeine could keep the Mac awake.
    static func canStayReachable(_ input: PanelInput) -> Bool {
        guard input.enabled, input.entitlement.allowsHolding else { return false }
        if case .safetyStop = input.decision.headline { return false }
        return true
    }

    /// Nil when the pose says it all. See `MenuBarLook`.
    static func menuBarAccessibilityLabel(_ input: PanelInput) -> String? {
        let pose = pose(input)
        if pose == .reachable, case .reachable(let until) = input.decision.headline {
            return PanelText.menuBarReachable(until, calendar: input.calendar, locale: input.locale)
        }
        // Drawn like "off", and the app is on.
        if pose == .off, case .notEntitled = input.decision.headline {
            return PanelText.menuBar(PanelText.headline(input.decision.headline).subtitle)
        }
        return nil
    }

    // MARK: Wake for jobs

    /// While an alarm is set and its time is ahead.
    static func wakeLine(_ input: PanelInput, now: Date) -> String? {
        guard let alarm = input.wakeAlarm, alarm.at > now else { return nil }
        return PanelText.wakesAt(alarm, now: now, calendar: input.calendar, locale: input.locale)
    }

    // MARK: Sleep note

    static func sleepNote(_ input: PanelInput) -> PanelAttention? {
        input.sleepNote.map {
            PanelAttention(
                kind: .sleptAnyway, text: PanelText.slept($0, calendar: input.calendar, locale: input.locale),
                actions: [.dismissSleepNote]
            )
        }
    }

    // MARK: Attention

    /// One line at a time, the most urgent first. Nil when all is well.
    static func attention(_ input: PanelInput) -> PanelAttention? {
        if case .safetyStop(let stop) = input.decision.headline {
            switch stop {
            case .batteryLow, .weakCharger:
                // The line of the battery says when it starts again. Once is enough.
                if battery(input) == nil {
                    let recovery = input.settings.batteryFloorPercent + SafetyMonitor.batteryRecoveryPoints
                    return PanelAttention(kind: .safetyStop, text: PanelText.startsAgain(atBatteryPercent: recovery))
                }
            case .tooHot:
                return PanelAttention(kind: .safetyStop, text: PanelText.startsAgainWhenCool)
            case .closedLid:
                return PanelAttention(kind: .safetyStop, text: PanelText.startsAgainWhenLidOpens)
            }
        }
        if input.flagLeftOn {
            return PanelAttention(
                kind: .helperSwitchedOff,
                text: PanelText.allowHelperAgain,
                actions: [.openLoginItems]
            )
        }
        // The robot keeps its pose: the Mac still stays awake with the lid open.
        if input.helperNotResponding {
            return PanelAttention(
                kind: .helperNotResponding,
                text: PanelText.helperNotResponding,
                actions: input.helperRepairTried ? [.tryHelperAgain, .openLoginItems] : [.tryHelperAgain]
            )
        }
        if input.helperLost {
            return PanelAttention(kind: .helperLost, text: PanelText.helperLost, actions: [.setUpLidClosed])
        }
        switch input.entitlement {
        case .expired(.trialOver):
            return PanelAttention(kind: .license, text: PanelText.buyToKeepAwake, actions: [.buy, .enterKey])
        case .expired(.unverified):
            return PanelAttention(kind: .license, text: PanelText.connectAndCheck, actions: [.checkLicense])
        case .expired(.activationRemoved):
            return PanelAttention(kind: .license, text: PanelText.activateAgain, actions: [.activateAgain, .enterKey])
        case .trial(let daysLeft) where daysLeft <= trialWarningDays:
            return PanelAttention(
                kind: .license,
                text: PanelText.trialEnds(inDays: daysLeft),
                actions: input.hasLicenseKey ? [.enterKey] : [.buy]
            )
        case .trial, .licensed:
            break
        }
        // Not to be dismissed: the user asked for what the lid takes away.
        if input.reachableUntil != nil, input.pausedUntil == nil, input.onBattery, input.lidClosedNeedsSetup {
            return PanelAttention(kind: .reachableNeedsLidClosed, text: PanelText.reachableNeedsLidClosed, actions: [.setUpLidClosed])
        }
        if input.lidClosedNeedsSetup && !input.lidClosedHintDismissed {
            return PanelAttention(
                kind: .lidClosedNotSetUp,
                text: PanelText.lidClosedNotSetUp,
                actions: [.setUpLidClosed, .dismissLidClosedHint]
            )
        }
        return nil
    }

    // MARK: Battery

    /// The battery floor stops every hold on battery, with the lid open
    /// too, and with the floor off the user has to see the end coming, so the line is there whenever Agent Caffeine could hold on
    /// battery, with or without the helper for a closed lid.
    static func battery(_ input: PanelInput) -> PanelBattery? {
        guard input.onBattery, let percent = input.batteryPercent,
              input.enabled, input.pausedUntil == nil, input.entitlement.allowsHolding else { return nil }
        let shown = min(max(percent, 0), 100)
        // With no floor the line still shows the end coming.
        guard input.settings.batteryFloorEnabled else {
            let reached = NoLimitBatteryWarning.levels.filter { percent <= $0 }.count
            return PanelBattery(percent: shown, floor: nil, level: [.normal, .nearFloor, .nearEmpty][reached])
        }
        let floor = input.settings.batteryFloorPercent
        var level = PanelBattery.Level.normal
        if case .safetyStop(.batteryLow) = input.decision.headline {
            level = .stopped
        } else if percent <= floor + batteryWarningPoints {
            level = .nearFloor
        }
        return PanelBattery(percent: shown, floor: floor, level: level)
    }

    /// The hint of the first time. Not for a helper that was set up
    /// before, and not while Agent Caffeine brings it back.
    static func lidClosedNeedsSetup(setup: HelperSetup, wasSetUp: Bool, wanted: Bool, hasBattery: Bool) -> Bool {
        hasBattery && wanted && !wasSetUp && (setup == .notSetUp || setup == .requiresApproval)
    }

    static func helperLost(setup: HelperSetup, wasSetUp: Bool, wanted: Bool, hasBattery: Bool) -> Bool {
        hasBattery && wanted && (setup == .lost || (setup == .requiresApproval && wasSetUp))
    }

    static func helperNotResponding(notResponding: Bool, wanted: Bool, hasBattery: Bool) -> Bool {
        hasBattery && wanted && notResponding
    }

    private static func licenseActions(_ input: PanelInput) -> [PanelAction] {
        switch input.entitlement {
        case .licensed: return []
        case .trial, .expired: return input.hasLicenseKey ? [.enterKey] : [.buy, .enterKey]
        }
    }

    // MARK: Groups

    /// One group for each agent. Agents with a session that waits come
    /// first, then the ones with a session that works, the longest at
    /// work on top, then the idle ones, the one that was active last on
    /// top. From the fifth idle agent on they go behind "more idle agents".
    /// The holds from the command line stand below the agents that wait
    /// or work, one line each.
    static func groups(_ input: PanelInput, now: Date) -> (inView: [PanelGroup], moreIdle: [PanelGroup]) {
        let readings = input.decision.perAgent.map(\.reading)
        var order: [String] = []
        var byAgent: [String: [AgentReading]] = [:]
        for reading in readings {
            if byAgent[reading.agentID] == nil { order.append(reading.agentID) }
            byAgent[reading.agentID, default: []].append(reading)
        }
        let names = groupNames(readings)
        let unordered = order.map { built(byAgent[$0] ?? [], name: names[$0] ?? "", input: input, now: now) }
        // Stable: agents of the same rank and start keep the order of the readings.
        let ordered = unordered.enumerated().sorted {
            let (a, b) = ($0.element, $1.element)
            if a.rank != b.rank { return a.rank < b.rank }
            if a.rank == .idle {
                let (sinceA, sinceB) = (a.since ?? .distantPast, b.since ?? .distantPast)
                return sinceA == sinceB ? $0.offset < $1.offset : sinceA > sinceB
            }
            let (sinceA, sinceB) = (a.since ?? .distantFuture, b.since ?? .distantFuture)
            return sinceA == sinceB ? $0.offset < $1.offset : sinceA < sinceB
        }.map(\.element)
        let all = distinguished(ordered, input: input)
        let active = all.filter { $0.kind == .active }.count
        let idle = all.count - active
        // A line that only hides one agent is no shorter than the agent.
        let inView = idle <= idleGroupsInView + 1 ? idle : idleGroupsInView
        let shown = Array(all.prefix(active)) + jobGroups(input, now: now) + holdGroups(input, now: now)
            + Array(all.dropFirst(active).prefix(inView))
        return (shown, Array(all.dropFirst(active + inView)))
    }

    /// The id of the line of a hold, in place of an `AgentDefinition.id`.
    /// No agent has a mark for it, so the line shows the terminal glyph.
    static func holdRowID(_ id: String) -> String { "hold:\(id)" }

    /// The id of the line of a job hold.
    static func jobRowID(_ id: String) -> String { "job:\(id)" }

    /// A job hold has a line like a hold from the command line, with
    /// "Stop".
    private static func jobGroups(_ input: PanelInput, now: Date) -> [PanelGroup] {
        let holding = input.decision.hold
        return input.decision.jobHolds.map { hold in
            let row = PanelRow(
                id: jobRowID(hold.id), agentID: jobRowID(hold.id), name: hold.title, label: nil, state: holding ? .working : .idle,
                detail: PanelText.jobHold(hold, holding: holding, now: now, calendar: input.calendar, locale: input.locale),
                hint: PanelText.jobHoldHint
            )
            return PanelGroup(header: row, working: holding ? 1 : 0, stop: .stopJobHold(id: hold.id))
        }
    }

    private static func holdGroups(_ input: PanelInput, now: Date) -> [PanelGroup] {
        let holding = input.decision.hold
        return input.decision.manualHolds.map { hold in
            let row = PanelRow(
                id: holdRowID(hold.id), agentID: holdRowID(hold.id), name: hold.title, label: nil, state: holding ? .working : .idle,
                detail: PanelText.hold(hold, holding: holding, now: now, calendar: input.calendar, locale: input.locale),
                hint: PanelText.holdHint
            )
            return PanelGroup(header: row, working: holding ? 1 : 0, stop: .stopHold(id: hold.id))
        }
    }

    /// A group, where it stands in the list, and the one session it
    /// stands for. A group of several sessions has none.
    private struct Built {
        enum Rank: Int, Comparable {
            case waiting
            case working
            case idle
            case ignored

            static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
        }

        var group: PanelGroup
        var identity: ProcessIdentity?
        var rank: Rank
        /// Since when the longest session waits or works, or when the
        /// last one went idle.
        var since: Date?
    }

    /// The name of each agent. A desktop app that is open next to the
    /// command line tool of the same name says that it is the app.
    private static func groupNames(_ readings: [AgentReading]) -> [String: String] {
        var names: [String: String] = [:]
        let commandLine = Set(readings.filter { $0.kind == .cli }.map(\.displayName))
        for reading in readings {
            let isApp = reading.kind == .desktop && commandLine.contains(reading.displayName)
            names[reading.agentID] = isApp ? PanelText.app(reading.displayName) : reading.displayName
        }
        return names
    }

    private static func built(_ readings: [AgentReading], name: String, input: PanelInput, now: Date) -> Built {
        let first = readings[0]
        let waiting = longestFirst(readings.filter { $0.verdict.state == .waitingForUser }, clock: input.clock)
        let working = longestFirst(readings.filter { $0.verdict.state == .working }, clock: input.clock)
        // Stable: the idle session that was active last comes first.
        let idle = readings.filter { $0.verdict.state == .idle }
            .map { (reading: $0, since: idleSince($0, clock: input.clock, now: now)) }
            .enumerated().sorted {
                let (a, b) = ($0.element.since ?? .distantPast, $1.element.since ?? .distantPast)
                return a == b ? $0.offset < $1.offset : a > b
            }.map(\.element)
        let active = waiting + working
        var header = PanelRow(id: first.agentID, agentID: first.agentID, name: name, label: nil, state: .idle, detail: "", hint: "")
        var rank = Built.Rank.idle
        var since = idle.first?.since
        if let longest = waiting.first {
            (header.state, rank, since) = (.waiting, .waiting, input.clock.since(longest.identity))
        } else if let longest = working.first {
            (header.state, rank, since) = (.working, .working, input.clock.since(longest.identity))
        }
        var group = PanelGroup(
            header: header, working: working.count, waiting: waiting.count, idle: idle.count, rule: input.settings.rule(for: first.agentID)
        )
        if readings.count == 1 { group.header.goTo = goTo(first, input: input) }
        if active.isEmpty, isIgnored(first) {
            group.header.detail = PanelText.ignored
            group.header.hint = first.verdict.reason.text
            return Built(group: group, identity: readings.count == 1 ? first.identity : nil, rank: .ignored, since: since)
        }
        if readings.count == 1 {
            group.header.label = active.isEmpty ? nil : input.labels[first.identity]
            group.header.detail = active.isEmpty
                ? PanelText.idle(seconds: since.map { now.timeIntervalSince($0) }, finished: input.clock.before(first.identity) == .working)
                : activeDetail(first, input: input, now: now)
            group.header.hint = first.verdict.reason.text
            return Built(group: group, identity: first.identity, rank: rank, since: since)
        }
        group.header.detail = PanelText.groupSummary(working: working.count, waiting: waiting.count, idle: idle.count)
        group.header.hint = group.header.detail
        if active.isEmpty {
            let listed = Array(idle.prefix(idleChildrenInView))
            group.children = zip(listed, childLabels(listed.map(\.reading), input: input)).map { session, label in
                child(session.reading, label: label, input: input, detail: PanelText.idle(
                    seconds: session.since.map { now.timeIntervalSince($0) },
                    finished: input.clock.before(session.reading.identity) == .working
                ))
            }
            if idle.count > listed.count {
                group.children.append(count(PanelText.andMore(idle.count - listed.count), agentID: first.agentID))
            }
        } else {
            group.children = zip(active, childLabels(active, input: input)).map { reading, label in
                child(reading, label: label, input: input, detail: activeDetail(reading, input: input, now: now))
            }
            if !idle.isEmpty {
                group.children.append(count(PanelText.idleSessions(idle.count), agentID: first.agentID))
            }
        }
        return Built(group: group, identity: nil, rank: rank, since: since)
    }

    /// Stable: sessions with the same start keep the order of the readings.
    private static func longestFirst(_ readings: [AgentReading], clock: StateClock) -> [AgentReading] {
        readings.enumerated().sorted {
            let (a, b) = (clock.since($0.element.identity) ?? .distantFuture, clock.since($1.element.identity) ?? .distantFuture)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    /// The phrase of a session that works or waits.
    private static func activeDetail(_ reading: AgentReading, input: PanelInput, now: Date) -> String {
        let seconds = input.clock.since(reading.identity).map { now.timeIntervalSince($0) }
        // An instance that was first seen in this state began before that.
        let startSeen = input.clock.before(reading.identity) != nil
        return reading.verdict.state == .working
            ? PanelText.working(reading.verdict.reason, seconds: seconds, startSeen: startSeen)
            : PanelText.waiting(seconds: seconds, startSeen: startSeen)
    }

    // MARK: Children

    private static func child(_ reading: AgentReading, label: String, input: PanelInput, detail: String) -> PanelChild {
        PanelChild(
            id: "\(reading.identity.pid):\(reading.identity.startTime)",
            label: label,
            detail: detail,
            hint: [input.labels[reading.identity], reading.verdict.reason.text].compactMap { $0 }.joined(separator: " · "),
            goTo: goTo(reading, input: input)
        )
    }

    private static func goTo(_ reading: AgentReading, input: PanelInput) -> PanelAction? {
        input.hosts[reading.identity].map { .goToAgent(reading.identity, app: $0) }
    }

    /// A line that counts sessions in place of their names.
    private static func count(_ text: String, agentID: String) -> PanelChild {
        PanelChild(id: "count:\(agentID)", label: text, detail: nil, hint: text)
    }

    /// What each session of one agent is called: its own name, else its
    /// folder, else its terminal, else when it started. Sessions that
    /// would read the same also get their terminal, else their start.
    static func childLabels(_ readings: [AgentReading], input: PanelInput) -> [String] {
        let hints = readings.map { input.hints[$0.identity] }
        let terminals = hints.map { $0?.terminal }
        let starts = readings.map { started($0.identity, input: input) }
        let plain = readings.indices.map { hints[$0]?.name ?? input.labels[readings[$0].identity] ?? terminals[$0] ?? starts[$0] }
        var labels = plain
        for indices in Dictionary(grouping: plain.indices, by: { plain[$0] }).values where indices.count > 1 {
            let among = indices.map { terminals[$0] }
            for (place, index) in indices.enumerated() {
                let terminal = unique(among, at: place).flatMap { $0 == plain[index] ? nil : $0 }
                let more = terminal ?? starts[index]
                labels[index] = more == plain[index] ? more : "\(plain[index]) · \(more)"
            }
        }
        return labels
    }

    // MARK: Same title

    /// Agents of one session whose lines would read the same get what
    /// tells them apart: the name of the session, else its terminal,
    /// else when it started.
    private static func distinguished(_ built: [Built], input: PanelInput) -> [PanelGroup] {
        var result = built.map(\.group)
        let sameTitle = Dictionary(grouping: built.indices.filter { built[$0].identity != nil }, by: { built[$0].group.header.title })
        for indices in sameTitle.values where indices.count > 1 {
            let hints = indices.map { built[$0].identity.flatMap { input.hints[$0] } }
            let names = hints.map { $0?.name }
            let terminals = hints.map { $0?.terminal }
            for (place, index) in indices.enumerated() {
                guard let identity = built[index].identity else { continue }
                result[index].header.distinction = unique(names, at: place) ?? unique(terminals, at: place) ?? started(identity, input: input)
            }
        }
        return result
    }

    /// The value at `place` when no other place has the same one.
    private static func unique(_ values: [String?], at place: Int) -> String? {
        guard let value = values[place], values.filter({ $0 == value }).count == 1 else { return nil }
        return value
    }

    private static func started(_ identity: ProcessIdentity, input: PanelInput) -> String {
        PanelText.started(Date(timeIntervalSince1970: identity.startTime), calendar: input.calendar, locale: input.locale)
    }

    private static func isIgnored(_ reading: AgentReading) -> Bool {
        reading.verdict.reason == .ignoredByRule
    }

    /// The verdict knows the quiet time of an agent that is judged by its
    /// activity, also from before the app saw it.
    private static func idleSince(_ reading: AgentReading, clock: StateClock, now: Date) -> Date? {
        let seen = clock.since(reading.identity)
        guard case .noActivity(let minutes) = reading.verdict.reason, minutes > 0 else { return seen }
        let quiet = now.addingTimeInterval(-TimeInterval(minutes) * 60)
        return seen.map { min($0, quiet) } ?? quiet
    }

    /// The folder a session runs in, as its label. Nil for the root folder,
    /// where background services run.
    static func sessionLabel(workingDirectory: String?) -> String? {
        guard let workingDirectory, workingDirectory != "/" else { return nil }
        let name = (workingDirectory as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
