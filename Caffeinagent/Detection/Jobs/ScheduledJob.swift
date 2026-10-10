import Foundation

/// A job that something on this Mac starts at set times: a launchd agent
/// with a calendar, a line of the crontab, or a cron job of Hermes Agent.
/// Agent Caffeine can wake the Mac for it when the user switches it on.
///
/// Privacy: a job holds when it runs and a short name, and nothing else.
/// No command line, no program arguments, no environment, no prompt and
/// no other content of the file it was found in is kept, in memory or on
/// disk. Crontab lines and plists hold secrets. Add no field that takes
/// text from the source without a rule that says what it can hold.
struct ScheduledJob: Equatable, Identifiable {
    enum Source: String, Codable, CaseIterable {
        /// `StartCalendarInterval` of a plist in `~/Library/LaunchAgents`.
        case launchd
        /// A line of the crontab of the user.
        case crontab
        /// A job in `~/.hermes/cron/jobs.json`.
        case hermes
    }

    static let nameLimit = 60

    /// The same for the same job at every reading, so the switch of the
    /// user stays with it. See each reader for what it is made of.
    var id: String
    var source: Source
    /// For the menu and Settings. One line of at most `nameLimit`
    /// characters: the label of a launchd job, the name of the command of
    /// a crontab line without its folder and arguments, the name of a
    /// Hermes job, or "Hermes job" with its id when it has no name of
    /// its own (`HermesJobReader`).
    var name: String
    var schedule: JobSchedule
    /// The switch of the user. Off for a job that was found: nothing is
    /// adopted by itself.
    var enabled = false
}

/// When a job runs.
enum JobSchedule: Equatable {
    /// A crontab line.
    case cron(CronExpression)
    /// `StartCalendarInterval` of launchd: one entry per dictionary. The
    /// job runs when any of them does.
    case calendar([CronExpression])
    /// What a scheduler says about its own job.
    case reported(ReportedSchedule)

    /// The first run after `now`, nil when none is known.
    func next(after now: Date, clock: JobClock) -> Date? {
        switch self {
        case .cron(let expression): return expression.next(after: now, clock: clock)
        case .calendar(let entries): return entries.compactMap { $0.next(after: now, clock: clock) }.min()
        case .reported(let schedule): return schedule.next(after: now, clock: clock)
        }
    }

    /// The next runs after `now` in order, at most `count`.
    func fireTimes(after now: Date, count: Int, clock: JobClock) -> [Date] {
        var times: [Date] = []
        var from = now
        while times.count < count, let time = next(after: from, clock: clock) {
            times.append(time)
            from = time
        }
        return times
    }

    /// True for a job that runs more often than every `gap` on average
    /// over the 24 hours after `now`: more than 48 times for half an
    /// hour. Such a job is not offered: the Mac would not sleep between
    /// two of its runs. Two runs close together once a day are not often.
    ///
    /// A whole day is counted, so the answer is the same at every time of
    /// day. A few next runs would say "often" before two runs that are
    /// close and "not often" after them.
    func runsMoreOften(than gap: TimeInterval, now: Date, clock: JobClock) -> Bool {
        if case .reported(let schedule) = self, schedule.cron == nil, let minutes = schedule.everyMinutes {
            return TimeInterval(minutes) * 60 < gap
        }
        guard gap > 0 else { return false }
        let limit = Int(JobWakeMemory.day / gap)
        let end = now.addingTimeInterval(JobWakeMemory.day)
        var runs = 0
        var from = now
        while runs <= limit, let time = next(after: from, clock: clock), time <= end {
            runs += 1
            from = time
        }
        return runs > limit
    }
}

/// The schedule of a job whose scheduler writes its next run itself, as
/// Hermes Agent does. That time wins over one that is worked out here: an
/// interval counts from the last run, which only the scheduler knows.
struct ReportedSchedule: Equatable {
    /// What the scheduler wrote. It can be in the past.
    var nextRun: Date?
    /// The expression of a cron kind job.
    var cron: CronExpression?
    /// The length of an interval kind job.
    var everyMinutes: Int?

    /// The reported time while it is ahead. After it, the expression
    /// says. An interval with no reported time ahead has no known run.
    func next(after now: Date, clock: JobClock) -> Date? {
        if let nextRun, nextRun > now { return nextRun }
        return cron?.next(after: now, clock: clock)
    }
}
