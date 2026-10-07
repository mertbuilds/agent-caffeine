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
    static let offTitle = "agent caffeine is off"
    static let pausedTitle = "agent caffeine is paused"
    /// A safety stop or a license that does not allow a hold: the reason
    /// stands below it.
    static let stoppedTitle = "agent caffeine has stopped"
    static let helperOffTitle = "Your Mac cannot sleep"
    static let helperOffReason = "The helper of agent caffeine was turned off in Login Items"

    /// In place of the list when no agent is open.
    /// - Parameter invites: nothing but a missing agent keeps the Mac from
    ///   staying awake. Not so in a stop, while off or paused, and while
    ///   the Mac stays awake without an agent.
    static func empty(invites: Bool) -> String {
        invites ? "Start an agent and agent caffeine keeps your Mac awake while it works" : noAgentOpen
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
        case .idle(.one(let name)):
            return (canSleepTitle, "\(name) is idle")
        case .idle(.many):
            return (canSleepTitle, "All agents are idle")
        case .waitingReleased(let subject):
            return (canSleepTitle, phrase(subject, one: "is waiting for you", many: "are waiting for you"))
        case .noAgents:
            return (canSleepTitle, noAgentOpen)
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
        case .notEntitled(.trialOver):
            return (stoppedTitle, "Your trial has ended")
        case .notEntitled(.unverified):
            return (stoppedTitle, "Your license was not checked for 30 days")
        case .notEntitled(.activationRemoved):
            return (stoppedTitle, "This Mac is no longer activated")
        }
    }

    private static func phrase(_ subject: HoldSubject, one: String, many: String) -> String {
        switch subject {
        case .one(let name): return "\(name) \(one)"
        case .many(let count): return "\(count) agents \(many)"
        }
    }

    // MARK: Sleep outlook

    /// The body of a notification about an agent that waits. Nil when
    /// something else keeps the Mac awake. With the lid open it says what
    /// agent caffeine does, never when the Mac sleeps: the sleep timer of
    /// macOS and other apps decide that.
    static func sleepOutlook(_ outlook: SleepOutlook) -> String? {
        switch outlook {
        case .silent: return nil
        case .sleeps(let after): return "Your Mac sleeps in \(timeLeft(after))"
        case .letsGo(let after, _): return "agent caffeine keeps your Mac awake for \(moreTime(after))"
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
    /// the menu bar: "agent caffeine: your Mac stays awake".
    static func menuBar(_ state: String) -> String {
        "agent caffeine: \(state.prefix(1).lowercased() + state.dropFirst())"
    }

    static let menuBarAwake = menuBar(awakeTitle)
    static let menuBarWaiting = menuBar("An agent is waiting for you")
    static let menuBarCanSleep = menuBar(canSleepTitle)
    static let menuBarPaused = menuBar("Paused")
    static let menuBarOff = menuBar("Off")
    static let menuBarNeedsAttention = menuBar("Needs attention")

    /// The five looks of the icon with a word or two each, for the setup
    /// window.
    static let iconLegend: [(pose: HeroPose, text: String)] = [
        (.awake(wisps: 2), "Awake"),
        (.attentive, "An agent is waiting for you"),
        (.asleep, "Your Mac can sleep, or paused"),
        (.off, "Off, or the trial has ended"),
        (.safetyStop(.battery), "Needs attention"),
    ]

    // MARK: After a sleep

    /// "Your Mac slept at 02:14: the battery was at 20%".
    static func slept(_ note: SleepNote, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Your Mac slept at \(time(note.at, calendar: calendar, locale: locale)): \(sleepReason(note.reason))"
    }

    private static func sleepReason(_ reason: SleepReason) -> String {
        switch reason {
        case .lidClosedNoHelper: return "the lid was closed on battery and the helper is not set up"
        case .lidClosedSettingOff: return "the lid was closed on battery and staying awake with the lid closed is turned off"
        case .battery(let percent): return "the battery was at \(Self.percent(percent))"
        case .tooHot: return "your Mac got too hot"
        case .paused: return "agent caffeine was paused"
        case .notEntitled(.trialOver): return "your trial has ended"
        case .notEntitled(.unverified): return "your license was not checked for 30 days"
        case .notEntitled(.activationRemoved): return "this Mac is no longer activated"
        case .waitedTooLong(let subject, let hold):
            let length = HumaneDuration.length(seconds: hold) ?? "a moment"
            return "\(phrase(subject, one: "waited", many: "waited")) for you longer than \(length)"
        }
    }

    // MARK: Settings and the setup window

    /// Where the hooks are offered.
    static let hooksExplained = "Some agents can tell agent caffeine what they are doing. For that, agent caffeine adds a few lines to the agent's settings file and saves a copy of the file first. It never reads what you type."
    static let hooksOptionalInSetup = "If you skip this, agent caffeine still works."
    static let hooksOptionalInSettings = "agent caffeine still works without this."

    /// Where the helper for a closed lid is offered.
    static let lidClosedExplained = "On battery, macOS puts your Mac to sleep when you close the lid, even while an agent is working. agent caffeine can prevent that with a small helper that you allow once."
    static let helperExplained = "The helper is a background item of agent caffeine. It changes one sleep setting of macOS while agent caffeine keeps your Mac awake, and changes it back after."
    static let helperRemoveHere = "You can remove it here at any time."
    static let helperRemoveInSettings = "You can remove it in Settings > Battery and lid at any time."
    static let closedBagWarning = "Do not put your Mac in a closed bag while an agent works."
    static let allowInLoginItems = "Allow agent caffeine in System Settings > General > Login Items."
    static let helperIsSetUp = "The helper is set up"
    static let moveToApplicationsToSetUp = "Move agent caffeine to the Applications folder to set this up."
    static let moveToApplicationsToUse = "Move agent caffeine to the Applications folder to use this."

    /// In Settings > License, from what Polar said at the activation.
    static func keyRunsOn(macs: Int) -> String {
        "This key runs on \(HumaneDuration.counted(macs, "Mac"))."
    }

    static let openAtLogin = "Open agent caffeine at login"
    static let openAtLoginInSetup = "Open agent caffeine when you log in"

    // MARK: Trial

    /// The whole days of the trial, from the rule of the license.
    static let trialDays = Int(LicenseRules.trialLength / LicenseRules.day)

    /// On the last page of the setup window.
    static let trialIntro = "Your free trial runs for \(HumaneDuration.counted(trialDays, "day")). \(trialThen)"
    static let trialThen = "After that, agent caffeine needs a license key to keep your Mac awake."

    /// In Settings > License: "Your free trial has 5 days left.", and in
    /// the last 24 hours the day it ends on.
    static func trialStatus(daysLeft: Int, end: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard daysLeft <= 1 else { return "Your free trial has \(HumaneDuration.counted(daysLeft, "day")) left." }
        return "Your free trial ends \(trialEndDay(end, now: now, calendar: calendar))."
    }

    /// The last 24 hours of a trial end today or tomorrow.
    private static func trialEndDay(_ end: Date?, now: Date, calendar: Calendar) -> String {
        guard let end, !calendar.isDate(end, inSameDayAs: now) else { return "today" }
        return "tomorrow"
    }

    static func notification(_ notice: TrialNotice, end: Date?, now: Date, calendar: Calendar = .current) -> String {
        switch notice {
        case .endsSoon:
            return "Your agent caffeine trial ends \(trialEndDay(end, now: now, calendar: calendar)). After that it does not keep your Mac awake without a license key."
        case .ended:
            return "Your agent caffeine trial has ended. agent caffeine does not keep your Mac awake until you enter a license key."
        }
    }

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
        "agent caffeine starts again at \(Self.percent(percent))"
    }

    /// For VoiceOver.
    static func startsAgainSpoken(atBatteryPercent percent: Int) -> String {
        "agent caffeine starts again at \(percent) percent"
    }

    static let startsAgainWhenCool = "agent caffeine starts again when your Mac is cool"
    static let allowHelperAgain = "Allow agent caffeine again in Login Items, and your Mac sleeps as usual"
    static let buyToKeepAwake = "Buy a key to keep your Mac awake"
    static let connectAndCheck = "Connect to the internet, then check again"
    static let activateAgain = "Activate this Mac again to keep it awake"
    static let helperNotResponding = "agent caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery."
    static let helperRepairing = "Setting up the helper again…"
    static let helperLost = "agent caffeine has to set up its helper again"
    static let lidClosedNotSetUp = "Your Mac still sleeps with the lid closed on battery"

    static func trialEnds(inDays days: Int) -> String {
        "Your trial ends in \(HumaneDuration.counted(days, "day"))"
    }

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
        "Battery \(percent) percent, agent caffeine lets your Mac sleep at \(floor) percent"
    }

    static func batterySpokenStopped(percent: Int, recovery: Int) -> String {
        "Battery \(percent) percent, \(startsAgainSpoken(atBatteryPercent: recovery))"
    }

    // MARK: Actions

    static func title(of action: PanelAction) -> String {
        switch action {
        case .openLoginItems: return "Open System Settings"
        case .tryHelperAgain: return "Try again"
        case .buy: return "Buy from $19"
        case .enterKey: return "Enter license key…"
        case .checkLicense: return "Check now"
        case .activateAgain: return "Activate again"
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
        case .runningCommand, .backgroundJob:
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

    /// What tells a session apart when nothing else does: "since 14:05",
    /// or "since 2:05 PM" for a user who set the 12-hour clock.
    static func started(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "since \(time(date, calendar: calendar, locale: locale))"
    }

    // MARK: Bottom bar

    static let modePicker = "Keep your Mac awake"
    static let preferences = "Settings…"
    static let buyInMenu = "Buy agent caffeine from $19"
    static let help = "Help…"
    static let quit = "Quit agent caffeine"
    static let gearMenu = "Settings and more"
    static let timerMenu = "Pause or stay reachable"
    static let mainSwitch = "agent caffeine"
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"
}
