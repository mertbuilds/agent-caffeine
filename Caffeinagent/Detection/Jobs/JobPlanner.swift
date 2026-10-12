import Foundation

/// The alarm that Agent Caffeine wants: the Mac wakes at `at` for the job
/// that runs at `fireAt`.
struct JobAlarm: Equatable {
    var at: Date
    var fireAt: Date
    var jobID: String
    var jobName: String
}

/// One line of the list of jobs in Settings.
struct JobRun: Equatable {
    var job: ScheduledJob
    /// The next run, nil when none is known.
    var fireAt: Date?
    /// It runs more often than `JobSettings.minimumGap`, so it is shown
    /// and cannot be switched on.
    var tooOften: Bool
}

/// Why no alarm is wanted.
enum NoAlarmReason: Equatable {
    /// "Wake for jobs" is off.
    case featureOff
    case safetyStop
    case switchedOff
    case paused
    /// On battery, with "only on power" on.
    case onBattery
    /// On battery with the battery floor off: nothing would stop a Mac
    /// that wakes itself until it is empty.
    case batteryFloorOff
    /// On battery, and the level could not be read.
    case batteryUnknown
    /// On battery at the floor plus `JobSettings.batteryMargin` or below.
    case batteryLow
    case dailyLimit
    case noJobSwitchedOn
    /// The jobs that are on have no run that an alarm can be set for.
    case noRunKnown
    /// The next run is more than `WakeAlarmLimits.maximumLead` ahead. The
    /// helper takes no time that far, so none is asked for until it is
    /// closer.
    case tooFarAhead
}

struct JobPlan: Equatable {
    /// At most one: the alarm for the nearest job. A new plan after it
    /// rang gives the next one.
    var alarm: JobAlarm?
    /// Nil with an alarm.
    var noAlarm: NoAlarmReason?
    /// Every job that was found, the next to run first. A job with no
    /// known run is last.
    var nextRuns: [JobRun]
}

/// What the planner is told about the Mac and the app.
struct JobPlanContext: Equatable {
    /// The main switch of Agent Caffeine.
    var enabled = true
    var pausedUntil: Date?
    var safety: SafetyStop?
    var onBattery = false
    /// Nil on a Mac without a battery, and when it could not be read.
    var batteryPercent: Int?
    var batteryFloorEnabled = true
    var batteryFloorPercent = SafetyMonitor.defaultBatteryFloorPercent
    /// False for the plan that is made when the Mac is about to sleep.
    var macAwake = true
    /// The alarms that rang in the last 24 hours. The caller counts them.
    var wakesInLastDay = 0
    /// The alarm the helper confirmed and that did not ring yet.
    var alarmSet: JobAlarm?
}

/// Decides for which job the Mac is woken next. Pure: the jobs come with
/// the switches of the user (`JobSettings.applied`), and the caller
/// passes the time and the clock.
///
/// One alarm at a time, for the nearest job that is switched on, set
/// `leadTime` before the job. Every stop of `HoldPolicy` also stops the
/// alarm, and so does a battery that is low: a Mac that was woken cannot
/// be put back.
enum JobPlanner {
    static func plan(jobs: [ScheduledJob], settings: JobSettings, context: JobPlanContext, now: Date, clock: JobClock) -> JobPlan {
        let runs = jobs.enumerated().map { index, job in
            (index, JobRun(
                job: job, fireAt: job.schedule.next(after: now, clock: clock),
                tooOften: job.schedule.runsMoreOften(than: JobSettings.minimumGap)
            ))
        }
        let nextRuns = runs.sorted { first, second in
            switch (first.1.fireAt, second.1.fireAt) {
            case (let a?, let b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return first.0 < second.0
            }
        }.map(\.1)
        if let reason = stop(settings: settings, context: context, now: now) {
            return JobPlan(noAlarm: reason, nextRuns: nextRuns)
        }
        let wanted = nextRuns.filter { $0.job.enabled && !$0.tooOften && $0.job.noSwitch == nil }
        guard !wanted.isEmpty else { return JobPlan(noAlarm: .noJobSwitchedOn, nextRuns: nextRuns) }
        // A new alarm that is too close is refused, so the run after it
        // counts.
        let closest = context.macAwake ? JobSettings.nearWindow : settings.leadTime + JobSettings.minimumAhead
        let from = now.addingTimeInterval(closest)
        var alarm: JobAlarm?
        for run in wanted {
            // An alarm that is set stays as it is while its job is on and
            // its run is still the next one. The Mac wakes by itself in
            // the last seconds before an alarm too, and a plan that
            // moved the alarm then would lose the run.
            if let set = context.alarmSet, set.jobID == run.job.id, let next = run.fireAt, next == set.fireAt, next <= from {
                if alarm.map({ next < $0.fireAt }) ?? true { alarm = set }
                continue
            }
            guard let fireAt = run.fireAt.flatMap({ $0 > from ? $0 : nil }) ?? run.job.schedule.next(after: from, clock: clock) else { continue }
            if alarm.map({ fireAt < $0.fireAt }) ?? true {
                alarm = JobAlarm(at: fireAt.addingTimeInterval(-settings.leadTime), fireAt: fireAt, jobID: run.job.id, jobName: run.job.name)
            }
        }
        if let alarm, alarm.at.timeIntervalSince(now) > WakeAlarmLimits.maximumLead {
            return JobPlan(noAlarm: .tooFarAhead, nextRuns: nextRuns)
        }
        return JobPlan(alarm: alarm, noAlarm: alarm == nil ? .noRunKnown : nil, nextRuns: nextRuns)
    }

    /// The stops in the order of `HoldPolicy`, then the battery.
    private static func stop(settings: JobSettings, context: JobPlanContext, now: Date) -> NoAlarmReason? {
        guard settings.wakeForJobs else { return .featureOff }
        if context.safety != nil { return .safetyStop }
        guard context.enabled else { return .switchedOff }
        if let pausedUntil = context.pausedUntil, now < pausedUntil { return .paused }
        if let reason = batteryStop(settings: settings, context: context) { return reason }
        if context.wakesInLastDay >= settings.maxWakesPerDay { return .dailyLimit }
        return nil
    }

    /// Why no alarm is set on battery, nil on power and where the user
    /// and the charge allow it. A job hold follows the same rule: an
    /// alarm that was set on power can wake a Mac that was unplugged
    /// while it slept, and nothing keeps it awake then.
    static func batteryStop(settings: JobSettings, context: JobPlanContext) -> NoAlarmReason? {
        guard context.onBattery else { return nil }
        if settings.onPowerOnly { return .onBattery }
        guard context.batteryFloorEnabled else { return .batteryFloorOff }
        guard let percent = context.batteryPercent else { return .batteryUnknown }
        if percent <= context.batteryFloorPercent + JobSettings.batteryMargin { return .batteryLow }
        return nil
    }
}
