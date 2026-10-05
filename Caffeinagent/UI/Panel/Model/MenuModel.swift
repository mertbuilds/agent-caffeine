import Foundation

/// What the menu shows, worked out from the decision. Pure: the caller
/// passes the time.
enum MenuModel {
    /// Idle agents in view before the rest goes behind "more idle".
    static let idleRowsInView = 3
    /// The trial is named in the menu from this many days left.
    static let trialWarningDays = 2

    static let awakeTitle = "Your Mac stays awake"
    static let canSleepTitle = "Your Mac can sleep"
    static let offTitle = "agent caffeine is off"

    /// In place of the list when no agent is open. In the mode "always"
    /// the Mac stays awake without one.
    static func emptyText(mode: AwakeMode) -> String {
        mode == .always ? "No agent is open" : "Start an agent and agent caffeine keeps your Mac awake while it works"
    }

    static func state(_ input: PanelInput, now: Date) -> PanelState {
        let headline = input.decision.headline
        let (title, subtitle) = headlineTexts(headline, waitingFor: waitingHoldLeft(input, now: now))
        let (rows, moreIdle) = rows(input, now: now)
        return PanelState(
            pose: pose(for: headline),
            title: title,
            subtitle: subtitle,
            attention: attention(input),
            rows: rows,
            moreIdle: moreIdle,
            emptyText: input.decision.perAgent.isEmpty ? emptyText(mode: input.mode) : nil,
            licenseActions: licenseActions(input)
        )
    }

    // MARK: Hero

    static func pose(for headline: HoldHeadline) -> HeroPose {
        switch headline {
        case .working(.one): return .awake(wisps: 1)
        case .working(.many(let count)): return .awake(wisps: min(max(count, 1), 3))
        case .finishedRecently, .open, .alwaysOn, .remoteAccess: return .awake(wisps: 1)
        case .waitingHeld: return .attentive
        case .idle, .waitingReleased, .noAgents: return .asleep
        case .safetyStop(.batteryLow): return .safetyStop(.battery)
        case .safetyStop(.tooHot): return .safetyStop(.heat)
        case .switchedOff, .notEntitled: return .off
        }
    }

    /// The outcome, then the reason.
    /// - Parameter waitingFor: how long the Mac still stays awake for an
    ///   agent that waits, when that is known.
    static func headlineTexts(_ headline: HoldHeadline, waitingFor: TimeInterval? = nil) -> (title: String, subtitle: String) {
        switch headline {
        case .working(let subject):
            return (awakeTitle, phrase(subject, one: "is working", many: "are working"))
        case .waitingHeld(let subject):
            let waits = phrase(subject, one: "waits for you", many: "wait for you")
            guard let waitingFor else { return (awakeTitle, waits) }
            let minutes = max(1, Int((waitingFor / 60).rounded(.up)))
            return (awakeTitle, "\(waits), for \(minutes) more \(minutes == 1 ? "minute" : "minutes")")
        case .finishedRecently(let subject):
            return (awakeTitle, phrase(subject, one: "finished a moment ago", many: "finished a moment ago"))
        case .open(let subject):
            return (awakeTitle, phrase(subject, one: "is open", many: "are open"))
        case .alwaysOn:
            return (awakeTitle, "Until you switch it off")
        case .remoteAccess:
            return (awakeTitle, "Phone access is on")
        case .idle(.one(let name)):
            return (canSleepTitle, "\(name) is idle")
        case .idle(.many):
            return (canSleepTitle, "All agents are idle")
        case .waitingReleased(let subject):
            return (canSleepTitle, phrase(subject, one: "waits for your answer", many: "wait for your answer"))
        case .noAgents:
            return (canSleepTitle, "No agent is open")
        case .safetyStop(.batteryLow(let percent)):
            return (canSleepTitle, "Battery at \(percent) percent")
        case .safetyStop(.tooHot):
            return (canSleepTitle, "It got too hot")
        case .switchedOff:
            return (offTitle, "Your Mac sleeps as usual")
        case .notEntitled(.trialOver):
            return (canSleepTitle, "The trial ended")
        case .notEntitled(.unverified):
            return (canSleepTitle, "License not checked for 30 days")
        case .notEntitled(.activationRemoved):
            return (canSleepTitle, "This Mac is no longer activated")
        }
    }

    private static func phrase(_ subject: HoldSubject, one: String, many: String) -> String {
        switch subject {
        case .one(let name): return "\(name) \(one)"
        case .many(let count): return "\(count) agents \(many)"
        }
    }

    /// Until the last waiting hold runs out. Nil when no agent holds by
    /// waiting, or when its start is not known.
    private static func waitingHoldLeft(_ input: PanelInput, now: Date) -> TimeInterval? {
        input.decision.perAgent
            .filter { $0.cause == .waitingForUser }
            .compactMap { input.clock.since($0.reading.identity) }
            .map { $0.addingTimeInterval(input.settings.waitingHold).timeIntervalSince(now) }
            .max()
    }

    // MARK: Attention

    /// One line at a time, the most urgent first. Nil when all is well.
    static func attention(_ input: PanelInput) -> PanelAttention? {
        if case .safetyStop(let stop) = input.decision.headline {
            switch stop {
            case .batteryLow:
                let recovery = input.settings.batteryFloorPercent + SafetyMonitor.batteryRecoveryPoints
                return PanelAttention(kind: .safetyStop, text: "Starts again when the battery is at \(recovery) percent")
            case .tooHot:
                return PanelAttention(kind: .safetyStop, text: "Starts again when your Mac has cooled down")
            }
        }
        if input.flagLeftOn {
            return PanelAttention(
                kind: .helperSwitchedOff,
                text: "agent caffeine was switched off in Login Items. Your Mac may not sleep until you allow it again",
                actions: [.openLoginItems]
            )
        }
        switch input.entitlement {
        case .expired(.trialOver):
            return PanelAttention(kind: .license, text: "Buy a key to keep your Mac awake", actions: [.buy, .enterKey])
        case .expired(.unverified):
            return PanelAttention(kind: .license, text: "Connect to the internet, then check again", actions: [.checkLicense])
        case .expired(.activationRemoved):
            return PanelAttention(kind: .license, text: "Activate this Mac again to keep it awake", actions: [.activateAgain, .enterKey])
        case .trial(let daysLeft) where daysLeft <= trialWarningDays:
            return PanelAttention(
                kind: .license,
                text: "The trial ends in \(HumaneDuration.counted(daysLeft, "day"))",
                actions: input.hasLicenseKey ? [.enterKey] : [.buy]
            )
        case .trial, .licensed:
            break
        }
        if input.lidClosedNeedsSetup && !input.lidClosedHintDismissed {
            return PanelAttention(
                kind: .lidClosedNotSetUp,
                text: "Lid closed on battery is not set up",
                actions: [.setUpLidClosed, .dismissLidClosedHint]
            )
        }
        return nil
    }

    static func lidClosedNeedsSetup(helper: HelperStatus, wanted: Bool, hasBattery: Bool) -> Bool {
        hasBattery && wanted && helper != .enabled
    }

    private static func licenseActions(_ input: PanelInput) -> [PanelAction] {
        switch input.entitlement {
        case .licensed: return []
        case .trial, .expired: return input.hasLicenseKey ? [.enterKey] : [.buy, .enterKey]
        }
    }

    // MARK: Rows

    /// Agents that work come first, the longest at work on top, then the
    /// ones that wait, each on its own line. Idle sessions of the same
    /// agent share one line when there are two or more. The idle agent
    /// that was active last is on top, and from the fourth on they go
    /// behind "more idle".
    static func rows(_ input: PanelInput, now: Date) -> (inView: [PanelRow], moreIdle: [PanelRow]) {
        let readings = input.decision.perAgent.map(\.reading)
        var rows: [PanelRow] = []
        for state in [WorkState.working, .waitingForUser] {
            let active = readings.filter { $0.verdict.state == state }
                .map { (reading: $0, since: input.clock.since($0.identity)) }
            // Stable: instances with the same start keep the order of the readings.
            let ordered = active.enumerated().sorted {
                let (a, b) = ($0.element.since ?? .distantFuture, $1.element.since ?? .distantFuture)
                return a == b ? $0.offset < $1.offset : a < b
            }
            rows += ordered.map { activeRow($0.element.reading, since: $0.element.since, label: input.labels[$0.element.reading.identity], now: now) }
        }
        let idle = idleRows(readings.filter { $0.verdict.state == .idle }, clock: input.clock, now: now)
        // A line that only hides one agent is no shorter than the agent.
        let inView = idle.count <= idleRowsInView + 1 ? idle.count : idleRowsInView
        return (rows + idle.prefix(inView), Array(idle.dropFirst(inView)))
    }

    private static func activeRow(_ reading: AgentReading, since: Date?, label: String?, now: Date) -> PanelRow {
        let byRule = reading.verdict.reason == .alwaysWorkingByRule
        return PanelRow(
            id: "\(reading.identity.pid):\(reading.identity.startTime)",
            agentID: reading.agentID,
            name: reading.displayName,
            label: label,
            state: reading.verdict.state == .working ? .working : .waiting,
            status: activeStatus(reading.verdict),
            // The rule says nothing about when work began.
            duration: byRule ? nil : since.map { HumaneDuration.text(seconds: now.timeIntervalSince($0)) },
            hint: reading.verdict.reason.text
        )
    }

    private static func activeStatus(_ verdict: AgentVerdict) -> String {
        if verdict.state == .waitingForUser { return "Waits for your answer" }
        switch verdict.reason {
        case .runningCommand, .backgroundJob: return verdict.reason.text
        case .alwaysWorkingByRule: return "Counts as working while it is open"
        default: return "Working"
        }
    }

    private static func idleRows(_ idle: [AgentReading], clock: StateClock, now: Date) -> [PanelRow] {
        var groups: [(readings: [AgentReading], since: Date?)] = []
        var index: [String: Int] = [:]
        for reading in idle {
            let since = idleSince(reading, clock: clock, now: now)
            if let at = index[reading.agentID] {
                groups[at].readings.append(reading)
                groups[at].since = [groups[at].since, since].compactMap { $0 }.max()
            } else {
                index[reading.agentID] = groups.count
                groups.append(([reading], since))
            }
        }
        let ordered = groups.enumerated().sorted {
            let (a, b) = ($0.element, $1.element)
            let (ignoredA, ignoredB) = (isIgnored(a.readings[0]), isIgnored(b.readings[0]))
            if ignoredA != ignoredB { return ignoredB }
            let (sinceA, sinceB) = (a.since ?? .distantPast, b.since ?? .distantPast)
            return sinceA == sinceB ? $0.offset < $1.offset : sinceA > sinceB
        }
        return ordered.map { _, group in
            let first = group.readings[0]
            let count = group.readings.count
            var row = PanelRow(
                id: "idle:\(first.agentID)", agentID: first.agentID, name: first.displayName, label: nil, state: .idle,
                status: "Idle", duration: nil, hint: first.verdict.reason.text
            )
            if isIgnored(first) {
                row.status = "Ignored"
            } else if count > 1 {
                row.status = "\(count) idle sessions"
                row.hint = row.status
            } else if let since = group.since, now.timeIntervalSince(since) >= 60 {
                row.duration = HumaneDuration.text(seconds: now.timeIntervalSince(since))
            }
            return row
        }
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
