import Foundation

/// Every line the menu shows, in one place. Each one is a phrase a person
/// would say, a duration always comes with "for" or "ago", and a label on
/// one line has no period.
enum PanelText {
    // MARK: Headline

    static let awakeTitle = "Your Mac stays awake"
    static let canSleepTitle = "Your Mac can sleep"
    static let offTitle = "agent caffeine is off"
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
    static func headline(_ headline: HoldHeadline, waitingFor: TimeInterval? = nil) -> (title: String, subtitle: String) {
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

    // MARK: Attention

    static func startsAgain(atBatteryPercent percent: Int) -> String {
        "agent caffeine starts again at \(percent) percent"
    }

    static let startsAgainWhenCool = "agent caffeine starts again when it is cool"
    static let allowHelperAgain = "Allow it again and your Mac sleeps as usual"
    static let buyToKeepAwake = "Buy a key to keep your Mac awake"
    static let connectAndCheck = "Connect to the internet, then check again"
    static let activateAgain = "Activate this Mac again to keep it awake"
    static let lidClosedNotSetUp = "Your Mac still sleeps with the lid closed on battery"

    static func trialEnds(inDays days: Int) -> String {
        "Your trial ends in \(HumaneDuration.counted(days, "day"))"
    }

    // MARK: Actions

    static func title(of action: PanelAction) -> String {
        switch action {
        case .openLoginItems: return "Open System Settings"
        case .buy: return "Buy for $9"
        case .enterKey: return "Enter license key…"
        case .checkLicense: return "Check now"
        case .activateAgain: return "Activate again"
        case .setUpLidClosed: return "Set up…"
        case .dismissLidClosedHint: return "Dismiss"
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
        "\(count) idle sessions"
    }

    static func moreIdle(_ count: Int) -> String {
        "\(count) more idle"
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
    static let mainSwitch = "agent caffeine"
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"
}
