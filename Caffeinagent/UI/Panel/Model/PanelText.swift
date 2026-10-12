import Foundation

/// Every line the menu shows, in one place. Each one is a phrase a person
/// would say, a duration always comes with "for" or "ago", and a label on
/// one line has no period.
enum PanelText {
    // MARK: Numbers

    /// The copy is English, so a number follows the English form in every
    /// region. The one place to change when the app gets a second language.
    static let copyLocale = Locale(identifier: "en")

    /// "88%", for a line on the screen. A label for VoiceOver spells
    /// "percent" out.
    static func percent(_ value: Int) -> String {
        value.formatted(.percent.locale(copyLocale))
    }

    // MARK: Headline

    static let awakeTitle = "Your Mac stays awake"
    static let canSleepTitle = "Your Mac can sleep"
    static let offTitle = "Agent Caffeine is off"
    static let pausedTitle = "Agent Caffeine is paused"
    /// A safety stop: the reason stands below it.
    static let stoppedTitle = "Agent Caffeine has stopped"
    static let helperOffTitle = "Your Mac cannot sleep"
    static let helperOffReason = "The helper of Agent Caffeine was turned off in Login Items"

    /// In place of the list when no agent is open.
    /// - Parameter invites: nothing but a missing agent keeps the Mac from
    ///   staying awake. Not so in a stop, while off or paused, and while
    ///   the Mac stays awake without an agent.
    static func empty(invites: Bool) -> String {
        invites ? "Start an agent and Agent Caffeine keeps your Mac awake while it works" : noAgentOpen
    }

    static let noAgentOpen = "No agent is open"
    /// Below the invitation, to the tools the user can add.
    static let agentNotListed = "My agent is not listed"

    /// The outcome, then the reason.
    /// - Parameter outlook: what happens when the hold for an agent that
    ///   waits ends.
    ///   - now: for a pause, to say whether it ends today or tomorrow.
    static func headline(
        _ headline: HoldHeadline, outlook: SleepOutlook = .silent,
        now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> (title: String, subtitle: String) {
        switch headline {
        case .working(let subject):
            return (awakeTitle, phrase(subject, one: "is working", many: "are working"))
        case .waitingHeld(let subject):
            let waiting = phrase(subject, one: "is waiting for you", many: "are waiting for you")
            return (awakeTitle, [waiting, waitingEnd(outlook)].compactMap { $0 }.joined(separator: ", "))
        case .finishedRecently(let subject):
            return (awakeTitle, phrase(subject, one: "finished a moment ago", many: "finished a moment ago"))
        case .open(let subject):
            return (awakeTitle, phrase(subject, one: "is open", many: "are open"))
        case .alwaysOn:
            return (awakeTitle, "Until you turn it off")
        case .remoteAccess:
            return (awakeTitle, reachableWhilePluggedIn)
        case .reachable(let until):
            return (awakeTitle, reachableUntil(until, calendar: calendar, locale: locale))
        case .manualHold(.one(let name)):
            return (awakeTitle, "\(name) asked for it")
        case .manualHold(.many(let count)):
            return (awakeTitle, "\(count) commands asked for it")
        case .scheduledJob(.one(let name)):
            return (awakeTitle, "For the job \(name)")
        case .scheduledJob(.many(let count)):
            return (awakeTitle, "For \(count) scheduled jobs")
        case .idle(.one(let name)):
            return (canSleepTitle, "\(name) is idle")
        case .idle(.many):
            return (canSleepTitle, "All agents are idle")
        case .waitingReleased(let subject):
            return (canSleepTitle, phrase(subject, one: "is waiting for you", many: "are waiting for you"))
        case .noAgents:
            return (canSleepTitle, noAgentOpen)
        case .agentsStopped(.offline):
            return (canSleepTitle, offlineAgents)
        case .agentsStopped(.closedLid(let stop)):
            return (canSleepTitle, closedLidAgents(stop))
        case .safetyStop(.batteryLow(let percent)):
            return (stoppedTitle, "The battery is at \(Self.percent(percent))")
        case .safetyStop(.weakCharger(let percent)):
            return (stoppedTitle, "Your charger is too weak and the battery is at \(Self.percent(percent))")
        case .safetyStop(.tooHot):
            return (stoppedTitle, "Your Mac got too hot")
        case .switchedOff:
            return (offTitle, "Your Mac sleeps as usual")
        case .paused(let until):
            return (pausedTitle, startsAgain(at: until, now: now, calendar: calendar, locale: locale))
        }
    }

    private static func phrase(_ subject: HoldSubject, one: String, many: String) -> String {
        switch subject {
        case .one(let name): return "\(name) \(one)"
        case .many(let count): return "\(count) agents \(many)"
        }
    }

    // MARK: Offline

    /// Below the headline when nothing else keeps the Mac awake, and as
    /// the line below it when something else does. See `OfflineRule`.
    static let offlineAgents = "Your Mac is offline, so agents do not keep it awake"
    /// The line below an agent that works and does not keep the Mac awake.
    static let workingOffline = "Working, but your Mac is offline"

    /// "it was offline for 10 minutes", for the end of a sentence. Under
    /// a minute only with the hidden default of the tests.
    static func offlineReason(limit: TimeInterval) -> String {
        let length = HumaneDuration.length(seconds: limit) ?? HumaneDuration.counted(Int(limit), "second")
        return "it was offline for \(length)"
    }

    /// The text of the notification when the offline rule ends a hold,
    /// with the agents that still worked.
    static func offlineNotice(limit: TimeInterval, working: HoldSubject?) -> String {
        let text = "Agent Caffeine let your Mac sleep because \(offlineReason(limit: limit))"
        return working.map { "\(text). \(stillWorking($0))" } ?? text
    }

    static let offlineLimitPicker = "When your Mac is offline, stop staying awake for agents after"
    static let offlineLimitExplained = "Most agents cannot work without the internet. If your agents use a model on this Mac, choose Never. Command line holds and scheduled jobs are not stopped. Wi-Fi that is connected but has no internet does not count as offline."
    static let never = "Never"

    // MARK: Sleep outlook

    /// The body of a notification about an agent that waits. Nil when
    /// something else keeps the Mac awake. With the lid open it says what
    /// Agent Caffeine does, never when the Mac sleeps: the sleep timer of
    /// macOS and other apps decide that.
    static func sleepOutlook(_ outlook: SleepOutlook) -> String? {
        switch outlook {
        case .silent: return nil
        case .sleeps(let after): return "Your Mac sleeps in \(timeLeft(after))"
        case .letsGo(let after, _): return "Agent Caffeine keeps your Mac awake for \(moreTime(after))"
        }
    }

    /// The same below the headline "Your Mac stays awake", after the name
    /// of the agent.
    private static func waitingEnd(_ outlook: SleepOutlook) -> String? {
        switch outlook {
        case .silent: return nil
        case .sleeps(let after): return "your Mac sleeps in \(timeLeft(after))"
        case .letsGo(let after, _): return "for at least \(moreTime(after))"
        }
    }

    /// "5 minutes", rounded up to the full minute and never under one.
    private static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return HumaneDuration.length(seconds: TimeInterval(minutes) * 60) ?? HumaneDuration.counted(minutes, "minute")
    }

    /// "5 more minutes", and "1 hour 30 minutes more" from an hour on.
    private static func moreTime(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return minutes < 60 ? "\(minutes) more \(minutes == 1 ? "minute" : "minutes")" : "\(timeLeft(seconds)) more"
    }

    // MARK: Pause

    /// "15:30", or "3:30 PM" for a user who set the 12-hour clock.
    static func time(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Below the headline of a pause. A pause never ends later than tomorrow.
    static func startsAgain(at date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = time(date, calendar: calendar, locale: locale)
        return calendar.isDate(date, inSameDayAs: now) ? "Starts again at \(time)" : "Starts again tomorrow at \(time)"
    }

    /// In the bar at the bottom, in place of the mode.
    static func pausedUntil(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Paused until \(time(date, calendar: calendar, locale: locale))"
    }

    // MARK: Stay reachable

    /// Below the headline, and in the bar at the bottom in place of the mode.
    static func reachableUntil(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Reachable until \(time(date, calendar: calendar, locale: locale))"
    }

    /// For VoiceOver and the tooltip, on the item in the menu bar.
    static func menuBarReachable(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        menuBar(reachableUntil(date, calendar: calendar, locale: locale))
    }

    // MARK: Menu bar

    /// The state in words, for VoiceOver and the tooltip of the item in
    /// the menu bar: "Agent Caffeine: your Mac stays awake".
    static func menuBar(_ state: String) -> String {
        "Agent Caffeine: \(state.prefix(1).lowercased() + state.dropFirst())"
    }

    static let menuBarAwake = menuBar(awakeTitle)
    static let menuBarWaiting = menuBar("An agent is waiting for you")
    static let menuBarCanSleep = menuBar(canSleepTitle)
    static let menuBarPaused = menuBar("Paused")
    static let menuBarOff = menuBar("Off")
    static let menuBarNeedsAttention = menuBar("Needs attention")

    /// The four looks of the icon with a word or two each, for the setup
    /// window.
    static let iconLegend: [(pose: HeroPose, text: String)] = [
        (.awake(wisps: 2), "Awake"),
        (.attentive, "An agent is waiting for you"),
        (.asleep, "Your Mac can sleep, paused or off"),
        (.safetyStop(.battery), "Needs attention"),
    ]

    // MARK: After a sleep

    /// "Your Mac slept at 02:14: the battery was at 20%".
    static func slept(_ note: SleepNote, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Your Mac slept at \(time(note.at, calendar: calendar, locale: locale)): \(sleepReason(note.reason))"
    }

    /// "kept awake for 3 hours with the lid closed on battery", for the end
    /// of a sentence. The time is the time Agent Caffeine kept the Mac
    /// awake, not the time the lid was closed, so the words say who kept it
    /// awake: `keptAwake` is "it kept it awake" after "because", and "Agent
    /// Caffeine had kept it awake" after a sleep. Under a minute only with
    /// the hidden default of the tests.
    static func closedLidReason(_ stop: ClosedLidStop, keptAwake: String = "kept awake") -> String {
        switch stop {
        case .time(let seconds):
            let length = HumaneDuration.length(seconds: seconds) ?? HumaneDuration.counted(Int(seconds), "second")
            return "\(keptAwake) for \(length) with the lid closed on battery"
        case .drop(let points):
            return "the battery lost \(percent(points)) with the lid closed"
        }
    }

    /// "Kept awake for 3 hours with the lid closed on battery, so agents
    /// do not keep it awake". Below the headline when nothing else keeps
    /// the Mac awake, and as the line below it when something else does.
    static func closedLidAgents(_ stop: ClosedLidStop) -> String {
        let reason = closedLidReason(stop)
        return "\(reason.prefix(1).uppercased() + reason.dropFirst()), so agents do not keep it awake"
    }

    /// The line below an agent that works under the closed lid limit.
    static let workingPastLidLimit = "Working, but the closed lid limit is reached"

    /// "the closed lid limit of 3 hours", for the middle of a sentence.
    /// It names the limit as it is set, and not how long the Mac was
    /// kept awake.
    static func closedLidLimitName(_ stop: ClosedLidStop) -> String {
        switch stop {
        case .time(let seconds):
            let length = HumaneDuration.length(seconds: seconds) ?? HumaneDuration.counted(Int(seconds), "second")
            return "the closed lid limit of \(length)"
        case .drop(let points):
            return "the closed lid limit of \(percent(points)) of the battery"
        }
    }

    /// The text of the notification when the closed lid limit ends a
    /// hold, with the agents that still worked.
    /// - Parameter heldOn: another hold kept the Mac awake after the
    /// agents were let go, and ended now. The Mac was then kept awake for
    /// longer than the limit, so the text names the limit.
    static func closedLidNotice(_ stop: ClosedLidStop, heldOn: Bool = false, working: HoldSubject?) -> String {
        let text = heldOn
            ? "Agent Caffeine let your Mac sleep. Agents stopped keeping it awake earlier, when \(closedLidLimitName(stop)) was reached"
            : "Agent Caffeine let your Mac sleep because \(closedLidReason(stop, keptAwake: "it kept it awake"))"
        return working.map { "\(text). \(stillWorking($0))" } ?? text
    }

    /// "Claude Code was still working".
    static func stillWorking(_ subject: HoldSubject) -> String {
        phrase(subject, one: "was still working", many: "were still working")
    }

    private static func sleepReason(_ reason: SleepReason) -> String {
        switch reason {
        case .lidClosedNoHelper: return "the lid was closed on battery and the helper is not set up"
        case .lidClosedSettingOff: return "the lid was closed on battery and staying awake with the lid closed is turned off"
        case .battery(let percent): return "the battery was at \(Self.percent(percent))"
        case .tooHot: return "your Mac got too hot"
        case .closedLidLimit(let stop, let heldOn, let working):
            let reason = heldOn
                ? "\(closedLidLimitName(stop)) was reached earlier, so agents did not keep it awake"
                : closedLidReason(stop, keptAwake: "Agent Caffeine had kept it awake")
            return working.map { "\(reason), and \(stillWorking($0))" } ?? reason
        case .paused: return "Agent Caffeine was paused"
        case .offline(let limit, let working):
            let reason = offlineReason(limit: limit)
            return working.map { "\(reason), and \(stillWorking($0))" } ?? reason
        case .waitedTooLong(let subject, let hold):
            let length = HumaneDuration.length(seconds: hold) ?? "a moment"
            return "\(phrase(subject, one: "waited", many: "waited")) for you longer than \(length)"
        }
    }

    // MARK: Settings and the setup window

    /// Where the hooks are offered.
    static let hooksExplained = "Some agents can tell Agent Caffeine what they are doing. For that, Agent Caffeine adds a few lines to the agent's settings file and saves a copy of the file first. It never reads what you type."
    static let hooksOptionalInSetup = "If you skip this, Agent Caffeine still works."
    static let hooksOptionalInSettings = "Agent Caffeine still works without this."

    /// Where the helper for a closed lid is offered.
    static let lidClosedExplained = "On battery, macOS puts your Mac to sleep when you close the lid, even while an agent is working. Agent Caffeine can prevent that with a small helper that you allow once."
    static let helperExplained = "The helper is a background item of Agent Caffeine. It changes one sleep setting of macOS while Agent Caffeine keeps your Mac awake, and changes it back after."
    static let helperRemoveHere = "You can remove it here at any time."
    static let helperRemoveInSettings = "You can remove it in Settings > Battery and lid at any time."
    static let closedLidLimitPicker = "With the lid closed on battery, keep it awake for agents for at most"
    static let closedLidLimitExplained = "A last stop for agents, so a session that hangs does not empty the battery in a bag. Command line holds and scheduled jobs are not stopped"
    static let noLimit = "No limit"
    static let closedBagWarning = "Do not put your Mac in a closed bag while an agent works."
    static let lidChimeSwitch = "Play a sound when you close the lid and your Mac stays awake"
    static let lidChimeExplained = "You hear it only while Agent Caffeine keeps your Mac awake. No sound means your Mac goes to sleep."
    static let lidChimeInSetup = "You hear a short sound when you close the lid and your Mac stays awake."
    static let allowInLoginItems = "Allow Agent Caffeine in System Settings > General > Login Items."
    static let helperIsSetUp = "The helper is set up"
    static let moveToApplicationsToSetUp = "Move Agent Caffeine to the Applications folder to set this up."
    static let moveToApplicationsToUse = "Move Agent Caffeine to the Applications folder to use this."

    static let openAtLogin = "Open Agent Caffeine at login"
    static let openAtLoginInSetup = "Open Agent Caffeine when you log in"

    // MARK: Free and open source

    /// In Settings > About.
    static let freeAndOpenSource = "Free and open source"
    static let licenseExplained = "Agent Caffeine is free. You can read and change its source code under the GNU Affero General Public License, version 3."
    static let sourceCode = "Source code"
    static let openOnGitHub = "Open on GitHub"
    static let supportTheProject = "Support the project"
    static let payWhatYouWant = "Pay what you want"
    static let acknowledgements = "Acknowledgements"
    static let thirdPartyNotices = "Third-party notices"

    /// Below the choices, on battery.
    static let reachableCost = "Uses about \(percent(Reachable.batteryPercentPerHour)) of battery per hour"
    static let reachableNeedsLidClosed = "Close the lid and your Mac still sleeps. Set up the helper to stay reachable."
    /// Below the headline while the Mac stays awake on power for a tool's
    /// phone access.
    static let reachableWhilePluggedIn = "Reachable while plugged in"
    /// Over the two groups of the timer menu.
    static let pauseHeader = "Let your Mac sleep"
    static let reachableHeader = "Keep your Mac awake for messages from your phone"

    // MARK: Attention

    static func startsAgain(atBatteryPercent percent: Int) -> String {
        "Agent Caffeine starts again at \(Self.percent(percent))"
    }

    /// For VoiceOver.
    static func startsAgainSpoken(atBatteryPercent percent: Int) -> String {
        "Agent Caffeine starts again at \(percent) percent"
    }

    static let startsAgainWhenCool = "Agent Caffeine starts again when your Mac is cool"
    static let agentsAgainWhenLidOpens = "Agents keep your Mac awake again when you open the lid or connect power"
    static let allowHelperAgain = "Allow Agent Caffeine again in Login Items, and your Mac sleeps as usual"
    static let helperNotResponding = "Agent Caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery."
    static let helperRepairing = "Setting up the helper again…"
    static let helperLost = "Agent Caffeine has to set up its helper again"
    static let lidClosedNotSetUp = "Your Mac still sleeps with the lid closed on battery"

    // MARK: Battery

    /// The second half of the line, after the charge: lower case.
    static func batterySleepsAt(percent: Int) -> String {
        "sleeps at \(Self.percent(percent))"
    }

    static let batteryNoLimit = "no battery limit"
    static let batterySeparator = "·"

    static func batterySpokenNoLimit(percent: Int) -> String {
        "Battery \(percent) percent, no battery limit"
    }

    static func batteryStartsAgain(atPercent percent: Int) -> String {
        "starts again at \(Self.percent(percent))"
    }

    static func batterySpoken(percent: Int, floor: Int) -> String {
        "Battery \(percent) percent, Agent Caffeine lets your Mac sleep at \(floor) percent"
    }

    static func batterySpokenStopped(percent: Int, recovery: Int) -> String {
        "Battery \(percent) percent, \(startsAgainSpoken(atBatteryPercent: recovery))"
    }

    // MARK: Actions

    static func title(of action: PanelAction) -> String {
        switch action {
        case .openLoginItems: return "Open System Settings"
        case .tryHelperAgain: return "Try again"
        case .setUpLidClosed: return "Set up…"
        case .dismissLidClosedHint: return "Dismiss"
        case .pause(.thirtyMinutes): return "Pause for 30 minutes"
        case .pause(.oneHour): return "Pause for 1 hour"
        case .pause(.untilTomorrow): return "Pause until tomorrow"
        case .resume: return "Resume"
        case .stayReachable(.oneHour): return "Stay reachable for 1 hour"
        case .stayReachable(.twoHours): return "Stay reachable for 2 hours"
        case .stayReachable(.fourHours): return "Stay reachable for 4 hours"
        case .stopReachable: return "Stop"
        case .agentNotListed: return agentNotListed
        case .setAgentRule(_, .alwaysWorkingWhileOpen): return "This agent is working"
        case .setAgentRule(_, .ignore): return "Ignore this agent"
        case .setAgentRule(_, .automatic): return "Automatic"
        case .openAgentSettings: return "Open agent settings…"
        case .goToAgent(_, let app): return "Go to \(app)"
        case .stopHold, .stopJobHold: return "Stop"
        case .dismissSleepNote: return "Dismiss"
        case .openHelp: return help
        }
    }

    // MARK: Rows

    /// The tooltip of a line: what a click does, then the evidence.
    static func help(goTo: PanelAction?, hint: String) -> String {
        ([goTo?.title, hint] as [String?]).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The line below an agent that works.
    /// - Parameters:
    ///   - seconds: how long it has worked. Nil when that is not known.
    ///   - startSeen: the app saw the work begin.
    static func working(_ reason: VerdictReason, seconds: TimeInterval?, startSeen: Bool) -> String {
        let lasting = seconds.flatMap(HumaneDuration.lasting(seconds:))
        switch reason {
        case .alwaysWorkingByRule:
            // The rule says nothing about when work began.
            return "Always counts as working"
        case .runningCommand, .backgroundJob, .backgroundWork:
            return [reason.text, lasting].compactMap { $0 }.joined(separator: " ")
        default:
            if let lasting { return "Working \(lasting)" }
            return seconds != nil && startSeen ? "Started a moment ago" : "Working"
        }
    }

    /// The line below an agent that waits for the user.
    static func waiting(seconds: TimeInterval?, startSeen: Bool) -> String {
        if let lasting = seconds.flatMap(HumaneDuration.lasting(seconds:)) { return "Waiting for your answer \(lasting)" }
        return seconds != nil && startSeen ? "Asked you a moment ago" : "Waiting for your answer"
    }

    /// At the trailing edge of an idle agent.
    /// - Parameter finished: the app saw it work until it went idle.
    static func idle(seconds: TimeInterval?, finished: Bool) -> String {
        if let lasting = seconds.flatMap(HumaneDuration.lasting(seconds:)) { return "Idle \(lasting)" }
        return seconds != nil && finished ? "Finished a moment ago" : "Idle"
    }

    /// The title of the "finished" notification for a turn that the agent
    /// says ended with an error. The error itself is never shown.
    static func stoppedWithError(_ name: String) -> String {
        "\(name) stopped with an error"
    }

    static func idleSessions(_ count: Int) -> String {
        HumaneDuration.counted(count, "idle session")
    }

    /// At the trailing edge of an agent with several sessions: "2 working,
    /// 1 waiting for you", and "8 idle sessions" when none works or waits.
    static func groupSummary(working: Int, waiting: Int, idle: Int) -> String {
        let active = activeCounts(working: working, waiting: waiting)
        return active.isEmpty ? idleSessions(idle) : active.joined(separator: ", ")
    }

    /// For VoiceOver, with the idle sessions: "3 working, 8 idle".
    static func groupSpoken(working: Int, waiting: Int, idle: Int) -> String {
        let active = activeCounts(working: working, waiting: waiting)
        if active.isEmpty { return idleSessions(idle) }
        return (active + (idle > 0 ? ["\(idle) idle"] : [])).joined(separator: ", ")
    }

    private static func activeCounts(working: Int, waiting: Int) -> [String] {
        [working > 0 ? "\(working) working" : nil, waiting > 0 ? "\(waiting) waiting for you" : nil].compactMap { $0 }
    }

    /// Below the idle sessions that are listed.
    static func andMore(_ count: Int) -> String {
        "and \(count) more"
    }

    static func moreIdle(_ count: Int) -> String {
        HumaneDuration.counted(count, "more idle agent")
    }

    /// A desktop app next to the command line tool of the same name.
    static func app(_ name: String) -> String {
        "\(name) app"
    }

    static let ignored = "Ignored"

    // MARK: Holds from the command line

    /// The line below a hold from the command line.
    /// - Parameter holding: Agent Caffeine keeps the Mac awake. Not so in
    ///   a stop, where the hold is only asked for.
    static func hold(_ hold: ManualHold, holding: Bool, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let lead = holding ? "Keeps your Mac awake" : "Asked to keep your Mac awake"
        switch hold.kind {
        case .timed:
            return "\(lead) until \(time(hold.endsAt, calendar: calendar, locale: locale))"
        case .command:
            let lasting = holding ? HumaneDuration.lasting(seconds: now.timeIntervalSince(hold.startedAt)) : nil
            return ["\(lead) while it runs", lasting].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The tooltip of such a line.
    static let holdHint = "Asked for from the command line"

    // MARK: Settings, command line

    static let commandLineExplained = "A script or a long job can ask Agent Caffeine to keep your Mac awake, and an agent can ask through MCP. The battery limit, a pause and the switch still let your Mac sleep."
    static let commandLineInstallExplained = "This command makes a link to the tool in ~/.local/bin. Run it in Terminal."
    static let commandLineMCPExplained = "Add this to the MCP servers of your agent."

    // MARK: Settings, set up for agents

    static let agentSetupButton = "Set up for agents"
    static let agentSetupExplained = "A skill is a short text that tells an agent when to ask Agent Caffeine to keep your Mac awake, for example before a long build, and how."
    static let agentSetupOptional = "If you skip this, Agent Caffeine still works."
    static let agentSetupRemoveExplained = "Remove takes out the skill and the link, and nothing else."
    static let agentSetupTitle = "Let your agents keep your Mac awake"
    static let agentSetupDetails = "Details"
    static let agentSetupByHand = "Set up by hand"
    static let agentSetupUnavailable = "The skill is not in this copy of Agent Caffeine."
    static let commandLinkTitle = "The command agent-caffeine"

    /// "Claude Code, Codex and opencode".
    static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) and \(last)"
    }

    /// What the button does, from what is on this Mac: "Adds a skill to
    /// Claude Code, Codex and opencode, and links the command
    /// agent-caffeine." Nil when nothing is left to do.
    /// - Parameters:
    ///   - agents: the agents that get the skill.
    ///   - found: an agent that reads skills is on this Mac.
    ///   - foreign: an agent has a skill of that name that is not ours.
    static func agentSetupSummary(agents: [String], links: Bool, found: Bool, foreign: Bool = false) -> String? {
        switch (agents.isEmpty, links) {
        case (false, true): return "Adds a skill to \(list(agents)), and links the command agent-caffeine."
        case (false, false): return "Adds a skill to \(list(agents))."
        case (true, true):
            let linksOnly = "Links the command agent-caffeine."
            if !found { return "\(linksOnly) No agent that reads skills was found on this Mac." }
            return foreign ? "\(linksOnly) A skill named agent-caffeine that Agent Caffeine did not make is already there." : linksOnly
        case (true, false): return nil
        }
    }

    /// The one line after the setup: "Set up for Claude Code, Codex and 4
    /// more. The command agent-caffeine is linked." Nil when nothing of
    /// ours is there.
    /// - Parameter agents: the agents that have the skill.
    static func agentSetupDone(agents: [String], linked: Bool) -> String? {
        let named = agents.count > 3 ? Array(agents.prefix(2)) + ["\(agents.count - 2) more"] : agents
        let lines = [
            agents.isEmpty ? nil : "Set up for \(list(named)).",
            linked ? "The command agent-caffeine is linked." : nil,
        ]
        return lines.contains { $0 != nil } ? lines.compactMap { $0 }.joined(separator: " ") : nil
    }

    static func skillInstalled(in folder: String) -> String {
        "The skill is in \(folder)"
    }

    static func skillOutdated(in folder: String) -> String {
        "The skill in \(folder) is from another version of Agent Caffeine."
    }

    static func skillForeign(_ folder: String) -> String {
        "\(folder) was not made by Agent Caffeine, so it is left as it is."
    }

    static let skillNotInstalled = "No skill yet"
    static let commandLinked = "Linked in ~/.local/bin"
    static let commandNotLinked = "Not linked"
    static let commandLinkNeedsApplications = "Move Agent Caffeine to the Applications folder to link the command."

    static func localBinNotOnPath(file: String) -> String {
        "~/.local/bin does not seem to be on your PATH. If your shell does not find agent-caffeine, add this line to \(file)."
    }

    /// What tells a session apart when nothing else does: "since 14:05",
    /// or "since 2:05 PM" for a user who set the 12-hour clock.
    static func started(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "since \(time(date, calendar: calendar, locale: locale))"
    }

    // MARK: Bottom bar

    static let modePicker = "Keep your Mac awake"
    static let preferences = "Settings…"
    static let help = "Help…"
    static let quit = "Quit Agent Caffeine"
    static let gearMenu = "Settings and more"
    static let timerMenu = "Pause or stay reachable"
    static let mainSwitch = "Agent Caffeine"
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"
}
