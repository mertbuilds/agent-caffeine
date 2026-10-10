import Foundation

/// Every line of "Wake for jobs", in Settings and in the menu. The rules
/// of `PanelText` count here too: plain words, a label on one line has
/// no period, and a time is a time of day on the clock of the user.
///
/// A line names a job by its short name (`ScheduledJob.name`) and by
/// nothing else of it.
extension PanelText {
    // MARK: Settings

    static let jobsTitle = "Wake for jobs"
    static let jobsSwitch = "Wake your Mac for scheduled jobs"
    static let jobsNoneFound = "No scheduled job was found on this Mac."
    static let jobsPerJob = "Agent Caffeine wakes your Mac only for the jobs you switch on."
    static let jobsOnPowerOnly = "Only on power"
    /// A wake that was set on power can still come when the Mac was
    /// unplugged while it slept, so this does not say "does not wake".
    static let jobsOnPowerExplained = "On battery, Agent Caffeine sets no wake and keeps your Mac awake for no job."
    static let jobsOnBatteryWarning = "On battery with the lid closed this is not tested yet. Your Mac can wake in a bag."
    static let jobsShowHistory = "Show history"
    static let jobsHideHistory = "Hide history"
    static let jobsNoHistory = "Nothing happened yet."
    static let jobsTooOften = "Runs too often to wake for"
    static let jobsNoRunKnown = "No next run is known"

    /// Why a job is listed with no switch.
    static func jobNoSwitch(_ reason: ScheduledJob.NoSwitch) -> String {
        switch reason {
        case .sameLines: return "Two lines look the same, so Agent Caffeine cannot tell them apart"
        case .noPlainName: return "The command has no plain name, so Agent Caffeine cannot tell this line apart"
        }
    }
    /// The switch of a job was on and went off by itself. The same words
    /// as the line of the history, as a sentence.
    static func jobSwitchLost(_ name: String) -> String {
        "\(name) was switched off: two lines of the crontab look the same now."
    }
    static let jobsCloseNotice = "Close"
    static let jobsNeedHelper = "This needs the helper. Set it up under Lid closed first."

    /// "Wakes your Mac 1 minute before a job, keeps it awake while the
    /// job runs, for 30 minutes at most, then lets it sleep." The limit
    /// is said, because a job that runs longer is not waited for.
    static func jobsExplained(leadTime: TimeInterval, holdCap: TimeInterval) -> String {
        let lead = HumaneDuration.length(seconds: leadTime) ?? HumaneDuration.counted(Int(leadTime), "second")
        let cap = HumaneDuration.length(seconds: holdCap) ?? HumaneDuration.counted(Int(holdCap), "second")
        return "Wakes your Mac \(lead) before a job, keeps it awake while the job runs, for \(cap) at most, then lets it sleep."
    }

    /// The quiet line below a job that an agent runs, nil for any other
    /// job. Such a job is not watched while it runs: its hold ends
    /// `JobSettings.agentStartGrace` after its time, and from then on
    /// the Mac stays awake only while the agent is seen at work. With
    /// the lid closed it is not seen in this version (`JobHold`). So
    /// "while the job runs, for 30 minutes at most" is not true of it.
    static func jobAgentNote(_ source: ScheduledJob.Source) -> String? {
        guard source == .hermes else { return nil }
        let grace = JobSettings.agentStartGrace
        let bridge = HumaneDuration.length(seconds: grace) ?? HumaneDuration.counted(Int(grace), "second")
        return "Kept awake for \(bridge) after its time, then \(jobSource(source)) has to be seen working"
    }

    static func jobSource(_ source: ScheduledJob.Source) -> String {
        switch source {
        case .launchd: return "launchd agent"
        case .crontab: return "crontab"
        case .hermes: return "Hermes Agent"
        }
    }

    /// The quiet line for a source that is there and could not be read.
    static func jobSourceUnreadable(_ source: ScheduledJob.Source) -> String {
        switch source {
        case .launchd: return "Agent Caffeine could not read your launchd agents."
        case .crontab: return "Agent Caffeine could not read your crontab."
        case .hermes: return "Agent Caffeine could not read the jobs of Hermes Agent."
        }
    }

    /// Below the name of a job: "crontab · next run tomorrow at 03:00".
    static func jobDetail(_ run: JobRun, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let source = jobSource(run.job.source)
        if let reason = run.job.noSwitch { return "\(source) · \(jobNoSwitch(reason))" }
        if run.tooOften { return "\(source) · \(jobsTooOften)" }
        guard let fireAt = run.fireAt else { return "\(source) · \(jobsNoRunKnown)" }
        return "\(source) · next run \(when(fireAt, now: now, calendar: calendar, locale: locale))"
    }

    /// "at 09:14" today, "tomorrow at 09:14", and "on Mon, Oct 12 at
    /// 09:14" for a later day.
    static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = time(date, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        let formatter = DateFormatter()
        formatter.locale = copyLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return "on \(formatter.string(from: date)) at \(time)"
    }

    /// The one line of Settings that says where the feature stands. Nil
    /// when the switch says it all.
    static func jobStatus(_ status: JobWakeStatus, settings: JobSettings, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        switch status {
        case .off: return nil
        case .needsApplications: return moveToApplicationsToUse
        case .needsHelper: return jobsNeedHelper
        case .helperSilent:
            return "The helper gave no answer. It can be from an older version. Quit Agent Caffeine and open it again."
        case .asking: return "Setting the wake time…"
        case .alarmSet(let alarm):
            return "Next wake \(when(alarm.at, now: now, calendar: calendar, locale: locale)) for \(alarm.jobName)."
        case .refused(let reason): return "The helper did not set the wake time: \(refusal(reason)). Agent Caffeine tries again."
        case .noAlarm(let reason): return noAlarm(reason, settings: settings)
        }
    }

    private static func noAlarm(_ reason: NoAlarmReason, settings: JobSettings) -> String? {
        switch reason {
        case .featureOff: return nil
        case .safetyStop: return "No wake is set while Agent Caffeine has stopped to protect your Mac."
        case .switchedOff: return "No wake is set while Agent Caffeine is off."
        case .paused: return "No wake is set while Agent Caffeine is paused."
        case .notEntitled: return "No wake is set without a license key."
        case .onBattery: return "No wake is set while your Mac is on battery."
        case .batteryFloorOff: return "No wake is set on battery while the battery limit is off."
        case .batteryUnknown: return "No wake is set on battery: the charge could not be read."
        case .batteryLow: return "No wake is set: the battery is too low."
        case .dailyLimit: return "No wake is set: your Mac was woken \(HumaneDuration.counted(settings.maxWakesPerDay, "time")) in the last 24 hours."
        case .noJobSwitchedOn: return "Switch on a job, and Agent Caffeine wakes your Mac for it."
        case .noRunKnown: return "No wake is set: no next run is known for the jobs that are on."
        // Not "the next job": a run in the next minutes of an awake Mac
        // gets no wake, and the run after it is the one that is far.
        case .tooFarAhead: return "No wake is set yet: the next run to wake for is more than 8 days away."
        }
    }

    /// After "The helper did not set the wake time: ".
    static func refusal(_ reason: WakeAlarmRefusal) -> String {
        switch reason {
        case .notATime, .unknown: return "it did not take the time"
        case .tooSoon: return "the job is too close"
        case .tooFar: return "the job is more than 8 days away"
        case .tooOften: return "the time changed too often in one hour"
        case .notScheduled: return "macOS did not take it"
        case .notConfirmed: return "macOS did not list it"
        case .notCancelled: return "macOS did not take the old one away"
        }
    }

    // MARK: History

    /// One line of "Show history". The time of the event stands next to it.
    static func jobEvent(_ event: JobEvent, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let job = event.job ?? "a job"
        // At the start of a line.
        let first = event.job ?? "A job"
        let alarm = event.alarmAt.map { time(Date(timeIntervalSince1970: $0), calendar: calendar, locale: locale) }
        let wake = alarm.map { "The wake at \($0)" } ?? "The wake"
        switch event.kind {
        case .alarmSet: return ["Wake", alarm.map { "at \($0)" }, "set", event.job.map { "for \($0)" }].compactMap { $0 }.joined(separator: " ")
        case .alarmRefused:
            let reason = event.reason.flatMap(WakeAlarmRefusal.init(rawValue:)) ?? .unknown
            return "\(wake) was not set: \(refusal(reason))"
        case .helperSilent: return "The helper gave no answer"
        case .alarmCancelled: return "\(wake) was taken away"
        case .wokeAtAlarm: return "Your Mac woke for \(job)"
        case .alarmSeenLate: return "\(wake) passed while your Mac slept"
        case .alarmWhileAwake: return "Your Mac was awake at the wake time for \(job)"
        case .jobSeen: return "\(first) started"
        case .jobEnded: return "\(first) ended, and your Mac can sleep"
        case .endedByGrace: return "\(first) was not seen to start, and your Mac can sleep"
        case .endedByCap: return "\(first) ran longer than the limit, and your Mac can sleep"
        case .endedByStop: return "Stopped staying awake for \(job)"
        case .endedOnBattery: return "On battery, your Mac does not stay awake for \(job)"
        case .bridgeOver: return "The wait for \(job) is over"
        case .switchLost: return "\(first) was switched off: two lines of the crontab look the same now"
        }
    }

    // MARK: Menu

    /// The quiet line while an alarm is set: "Wakes at 09:14 for backup".
    static func wakesAt(_ alarm: JobAlarm, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Wakes \(when(alarm.at, now: now, calendar: calendar, locale: locale)) for \(alarm.jobName)"
    }

    /// The line below a job hold. Short, so it fits next to "Stop".
    /// - Parameter holding: Agent Caffeine keeps the Mac awake. Not so in
    ///   a stop, where the hold is only asked for.
    static func jobHold(_ hold: JobHold, holding: Bool, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard holding else { return "Asked to stay awake for a job" }
        if hold.seenAt != nil { return "Awake while the job runs" }
        return "Awake for the job at \(time(Date(timeIntervalSince1970: hold.fireAt), calendar: calendar, locale: locale))"
    }

    /// The tooltip of such a line.
    static let jobHoldHint = "A scheduled job you switched on in Settings"
}

extension PanelText {
    /// Next to a line of the history: "09:14" today, "Oct 12, 09:14"
    /// for another day.
    static func jobEventTime(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = time(date, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let formatter = DateFormatter()
        formatter.locale = copyLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(formatter.string(from: date)), \(time)"
    }
}
