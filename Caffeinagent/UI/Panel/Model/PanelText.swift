import Foundation

/// Every line the menu shows, in one place. Each one is a phrase a person
/// would say, a duration always comes with "for" or "ago", and a label on
/// one line has no period.
enum PanelText {
    // MARK: Headline

    static let awakeTitle = "Your Mac stays awake"
    static let canSleepTitle = "Your Mac can sleep"
    static let offTitle = "agent caffeine is off"
    static let pausedTitle = "agent caffeine is paused"
    static let helperOffTitle = "Your Mac may not sleep"
    static let helperOffReason = "agent caffeine was switched off in Login Items"

    /// In place of the list when no agent is open. In the mode "always"
    /// the Mac stays awake without one.
    static func empty(mode: AwakeMode) -> String {
        mode == .always ? "No agent is open" : "Start an agent and agent caffeine keeps your Mac awake while it works"
    }

    /// The outcome, then the reason.
    /// - Parameter waitingFor: how long the Mac still stays awake for an
    ///   agent that waits, when that is known.
    ///   - now: for a pause, to say whether it ends today or tomorrow.
    static func headline(
        _ headline: HoldHeadline, waitingFor: TimeInterval? = nil,
        now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current
    ) -> (title: String, subtitle: String) {
        switch headline {
        case .working(let subject):
            return (awakeTitle, phrase(subject, one: "is working", many: "are working"))
        case .waitingHeld(let subject):
            let waiting = phrase(subject, one: "is waiting for you", many: "are waiting for you")
            guard let waitingFor else { return (awakeTitle, waiting) }
            // The Mac may sleep then. Nothing says that it will.
            let minutes = max(1, Int((waitingFor / 60).rounded(.up)))
            return (awakeTitle, "\(waiting), can sleep in \(HumaneDuration.counted(minutes, "minute"))")
        case .finishedRecently(let subject):
            return (awakeTitle, phrase(subject, one: "finished a moment ago", many: "finished a moment ago"))
        case .open(let subject):
            return (awakeTitle, phrase(subject, one: "is open", many: "are open"))
        case .alwaysOn:
            return (awakeTitle, "Until you switch it off")
        case .remoteAccess:
            return (awakeTitle, "Phone access is on")
        case .reachable(let until):
            return (awakeTitle, reachableUntil(until, calendar: calendar, locale: locale))
        case .idle(.one(let name)):
            return (canSleepTitle, "\(name) is idle")
        case .idle(.many):
            return (canSleepTitle, "All agents are idle")
        case .waitingReleased(let subject):
            return (canSleepTitle, phrase(subject, one: "is waiting for your answer", many: "are waiting for your answer"))
        case .noAgents:
            return (canSleepTitle, "No agent is open")
        case .safetyStop(.batteryLow(let percent)):
            return (canSleepTitle, "The battery is at \(percent) percent")
        case .safetyStop(.tooHot):
            return (canSleepTitle, "Your Mac got too hot")
        case .switchedOff:
            return (offTitle, "Your Mac sleeps as usual")
        case .paused(let until):
            return (pausedTitle, startsAgain(at: until, now: now, calendar: calendar, locale: locale))
        case .notEntitled(.trialOver):
            return (canSleepTitle, "Your trial has ended")
        case .notEntitled(.unverified):
            return (canSleepTitle, "Your license was not checked for 30 days")
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

    /// For VoiceOver, on the item in the menu bar.
    static func menuBarReachable(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "agent caffeine, reachable until \(time(date, calendar: calendar, locale: locale))"
    }

    /// Below the choices, on battery.
    static let reachableCost = "Uses about \(Reachable.batteryPercentPerHour) percent of battery per hour"
    static let reachableNeedsLidClosed = "Close the lid and your Mac still sleeps. Set up lid closed to stay reachable"

    // MARK: Attention

    static func startsAgain(atBatteryPercent percent: Int) -> String {
        "agent caffeine starts again at \(percent) percent"
    }

    static let startsAgainWhenCool = "agent caffeine starts again when it is cool"
    static let allowHelperAgain = "Allow it again and your Mac sleeps as usual"
    static let buyToKeepAwake = "Buy a key to keep your Mac awake"
    static let connectAndCheck = "Connect to the internet, then check again"
    static let activateAgain = "Activate this Mac again to keep it awake"
    static let helperNotResponding = "agent caffeine cannot reach its helper. Your Mac will sleep when you close the lid on battery"
    static let helperRepairing = "Setting up the helper again…"
    static let helperLost = "agent caffeine has to set up its helper again"
    static let lidClosedNotSetUp = "Your Mac still sleeps with the lid closed on battery"

    static func trialEnds(inDays days: Int) -> String {
        "Your trial ends in \(HumaneDuration.counted(days, "day"))"
    }

    // MARK: Battery

    static func batteryLeft(percent: Int) -> String {
        "\(percent) percent battery"
    }

    static func batterySleepsBelow(percent: Int) -> String {
        "Sleeps below \(percent) percent"
    }

    static func batteryStartsAgain(atPercent percent: Int) -> String {
        "Starts again at \(percent) percent"
    }

    static func batterySpoken(percent: Int, floor: Int) -> String {
        "Battery \(percent) percent, agent caffeine lets your Mac sleep below \(floor) percent"
    }

    static func batterySpokenStopped(percent: Int, recovery: Int) -> String {
        "Battery \(percent) percent, \(startsAgain(atBatteryPercent: recovery))"
    }

    // MARK: Actions

    static func title(of action: PanelAction) -> String {
        switch action {
        case .openLoginItems: return "Open System Settings"
        case .tryHelperAgain: return "Try again"
        case .buy: return "Buy for $9"
        case .enterKey: return "Enter license key…"
        case .checkLicense: return "Check now"
        case .activateAgain: return "Activate again"
        case .setUpLidClosed: return "Set up…"
        case .dismissLidClosedHint: return "Dismiss"
        case .pause(.thirtyMinutes): return "Pause for 30 minutes"
        case .pause(.oneHour): return "Pause for 1 hour"
        case .pause(.untilTomorrow): return "Pause until tomorrow"
        case .resume: return "Resume now"
        case .stayReachable(.oneHour): return "Stay reachable for 1 hour"
        case .stayReachable(.twoHours): return "Stay reachable for 2 hours"
        case .stayReachable(.fourHours): return "Stay reachable for 4 hours"
        case .stopReachable: return "Stop staying reachable"
        }
    }

    // MARK: Rows

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

    /// What tells a session apart when nothing else does: "since 14:05".
    static func started(hour: Int, minute: Int) -> String {
        String(format: "since %02d:%02d", hour, minute)
    }

    // MARK: Bottom bar

    static let modePicker = "Keep your Mac awake"
    static let preferences = "Preferences…"
    static let buyInMenu = "Buy agent caffeine for $9"
    static let quit = "Quit agent caffeine"
    static let gearMenu = "Preferences and more"
    static let pauseMenu = "Pause"
    static let resume = "Resume"
    static let reachableMenu = "Stay reachable"
    static let timerMenu = "Pause or stay reachable"
    static let stop = "Stop"
    static let mainSwitch = "agent caffeine"
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"
}
