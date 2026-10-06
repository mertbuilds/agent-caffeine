import Foundation

/// What the menu shows, worked out from the decision. Pure: the caller
/// passes the time.
enum MenuModel {
    /// Idle agents in view before the rest goes behind "more idle".
    static let idleRowsInView = 3
    /// The trial is named in the menu from this many days left.
    static let trialWarningDays = 2

    static func state(_ input: PanelInput, now: Date) -> PanelState {
        let pose = pose(input)
        // The sleep flag is on with no helper to clear it, whatever the
        // decision says.
        let (title, subtitle) = pose == .helperOff
            ? (PanelText.helperOffTitle, PanelText.helperOffReason)
            : PanelText.headline(input.decision.headline, waitingFor: waitingHoldLeft(input, now: now))
        let (rows, moreIdle) = rows(input, now: now)
        return PanelState(
            pose: pose,
            title: title,
            subtitle: subtitle,
            attention: attention(input),
            rows: rows,
            moreIdle: moreIdle,
            emptyText: input.decision.perAgent.isEmpty ? PanelText.empty(mode: input.mode) : nil,
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
        case .working, .finishedRecently, .open, .alwaysOn, .remoteAccess: return .awake(wisps: 2)
        case .waitingHeld: return .attentive
        case .idle, .waitingReleased, .noAgents: return .asleep
        case .safetyStop(.batteryLow): return .safetyStop(.battery)
        case .safetyStop(.tooHot): return .safetyStop(.heat)
        case .switchedOff, .notEntitled: return .off
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
                return PanelAttention(kind: .safetyStop, text: PanelText.startsAgain(atBatteryPercent: recovery))
            case .tooHot:
                return PanelAttention(kind: .safetyStop, text: PanelText.startsAgainWhenCool)
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
        if input.lidClosedNeedsSetup && !input.lidClosedHintDismissed {
            return PanelAttention(
                kind: .lidClosedNotSetUp,
                text: PanelText.lidClosedNotSetUp,
                actions: [.setUpLidClosed, .dismissLidClosedHint]
            )
        }
        return nil
    }

    static func lidClosedNeedsSetup(helper: HelperStatus, wanted: Bool, hasBattery: Bool) -> Bool {
        hasBattery && wanted && helper != .enabled
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

    // MARK: Rows

    /// Agents that work come first, the longest at work on top, then the
    /// ones that wait, each on its own line. Idle sessions of the same
    /// agent share one line when there are two or more. The idle agent
    /// that was active last is on top, and from the fourth on they go
    /// behind "more idle".
    static func rows(_ input: PanelInput, now: Date) -> (inView: [PanelRow], moreIdle: [PanelRow]) {
        let readings = input.decision.perAgent.map(\.reading)
        var active: [SingleRow] = []
        for state in [WorkState.working, .waitingForUser] {
            let found = readings.filter { $0.verdict.state == state }
                .map { (reading: $0, since: input.clock.since($0.identity)) }
            // Stable: instances with the same start keep the order of the readings.
            let ordered = found.enumerated().sorted {
                let (a, b) = ($0.element.since ?? .distantFuture, $1.element.since ?? .distantFuture)
                return a == b ? $0.offset < $1.offset : a < b
            }
            active += ordered.map { SingleRow(row: activeRow($0.element.reading, input: input, now: now), identity: $0.element.reading.identity) }
        }
        let all = distinguished(active + idleRows(readings.filter { $0.verdict.state == .idle }, clock: input.clock, now: now), input: input)
        let idle = Array(all.dropFirst(active.count))
        // A line that only hides one agent is no shorter than the agent.
        let inView = idle.count <= idleRowsInView + 1 ? idle.count : idleRowsInView
        return (Array(all.prefix(active.count + inView)), Array(idle.dropFirst(inView)))
    }

    /// A line, and the one session it stands for. A line for several
    /// sessions has none.
    private struct SingleRow {
        var row: PanelRow
        var identity: ProcessIdentity?
    }

    private static func activeRow(_ reading: AgentReading, input: PanelInput, now: Date) -> PanelRow {
        let seconds = input.clock.since(reading.identity).map { now.timeIntervalSince($0) }
        // An instance that was first seen in this state began before that.
        let startSeen = input.clock.before(reading.identity) != nil
        let working = reading.verdict.state == .working
        return PanelRow(
            id: "\(reading.identity.pid):\(reading.identity.startTime)",
            agentID: reading.agentID,
            name: reading.displayName,
            label: input.labels[reading.identity],
            state: working ? .working : .waiting,
            detail: working
                ? PanelText.working(reading.verdict.reason, seconds: seconds, startSeen: startSeen)
                : PanelText.waiting(seconds: seconds, startSeen: startSeen),
            hint: reading.verdict.reason.text
        )
    }

    private static func idleRows(_ idle: [AgentReading], clock: StateClock, now: Date) -> [SingleRow] {
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
                detail: PanelText.idle(
                    seconds: group.since.map { now.timeIntervalSince($0) },
                    finished: clock.before(first.identity) == .working
                ),
                hint: first.verdict.reason.text
            )
            if isIgnored(first) {
                row.detail = PanelText.ignored
            } else if count > 1 {
                row.detail = PanelText.idleSessions(count)
                row.hint = row.detail
            }
            return SingleRow(row: row, identity: count == 1 ? first.identity : nil)
        }
    }

    // MARK: Same title

    /// Lines that would read the same get what tells them apart: the name
    /// of the session, else its terminal, else when it started.
    private static func distinguished(_ rows: [SingleRow], input: PanelInput) -> [PanelRow] {
        var result = rows.map(\.row)
        let sameTitle = Dictionary(grouping: rows.indices.filter { rows[$0].identity != nil }, by: { rows[$0].row.title })
        for indices in sameTitle.values where indices.count > 1 {
            let hints = indices.map { rows[$0].identity.flatMap { input.hints[$0] } }
            let names = hints.map { $0?.name }
            let terminals = hints.map { $0?.terminal }
            for (place, index) in indices.enumerated() {
                guard let identity = rows[index].identity else { continue }
                result[index].distinction = unique(names, at: place) ?? unique(terminals, at: place) ?? started(identity, calendar: input.calendar)
            }
        }
        return result
    }

    /// The value at `place` when no other place has the same one.
    private static func unique(_ values: [String?], at place: Int) -> String? {
        guard let value = values[place], values.filter({ $0 == value }).count == 1 else { return nil }
        return value
    }

    private static func started(_ identity: ProcessIdentity, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: identity.startTime))
        return PanelText.started(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
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
