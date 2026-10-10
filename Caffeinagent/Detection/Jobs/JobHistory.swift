import Foundation

/// One thing "Wake for jobs" did, for "Show history" in Settings. "It did
/// not wake" has many causes, and this list is how a user and the
/// support can tell them apart.
///
/// Privacy: an event holds its time, its kind, the time of the alarm and
/// the short name of the job (`ScheduledJob.name`). Nothing else of a job
/// is kept.
struct JobEvent: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        /// The helper put the alarm into the list of macOS.
        case alarmSet
        /// The helper said no. `reason` is the raw value of a `WakeAlarmRefusal`.
        case alarmRefused
        /// The helper said no to the time of the alarm that is set. The
        /// alarm stays until the lease of the helper is over.
        case renewalRefused
        /// The helper gave no answer, or is of a build without alarms.
        case helperSilent
        /// The helper took the alarm out of the list.
        case alarmCancelled
        /// The Mac slept, and Agent Caffeine ran again at the time of the alarm.
        case wokeAtAlarm
        /// The Mac slept, and Agent Caffeine ran again well after the
        /// time of the alarm: the alarm did not wake it, or the Mac
        /// slept again before the app got its turn.
        case alarmSeenLate
        /// The time of the alarm came while the Mac was awake.
        case alarmWhileAwake
        case jobSeen
        /// The job was seen to run and to end.
        case jobEnded
        /// The start grace passed and the job was not seen.
        case endedByGrace
        case endedByCap
        /// "Stop" in the menu, or the switch of the job or the feature.
        case endedByStop
        /// The Mac is on battery, and no alarm would be set there: the
        /// hold did not open, or it ended when the Mac was unplugged.
        case endedOnBattery
        /// The bridge for an agent job is over.
        case bridgeOver
        /// The switch of the job was on and went off by itself: another
        /// line of the crontab looks the same now, so the job has no
        /// switch any more (`ScheduledJob.NoSwitch.sameLines`).
        case switchLost
    }

    /// Seconds since the epoch.
    var at: TimeInterval
    var kind: Kind
    /// The time of the alarm, for the events of an alarm.
    var alarmAt: TimeInterval?
    var job: String?
    var reason: Int?

    var date: Date { Date(timeIntervalSince1970: at) }
}

/// The last events, the oldest first.
struct JobHistory: Codable, Equatable {
    static let limit = 50

    private(set) var events: [JobEvent] = []

    init(events: [JobEvent] = []) {
        self.events = Array(events.suffix(Self.limit))
    }

    mutating func note(_ kind: JobEvent.Kind, at now: Date, alarmAt: TimeInterval? = nil, job: String? = nil, reason: Int? = nil) {
        events.append(JobEvent(
            at: now.timeIntervalSince1970, kind: kind, alarmAt: alarmAt,
            job: ManualHold.clean(job, limit: ScheduledJob.nameLimit), reason: reason
        ))
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
    }
}

/// What "Wake for jobs" remembers between two launches of the app.
struct JobWakeMemory: Codable, Equatable {
    static let day: TimeInterval = 86_400

    /// The times of the alarms that came while the Mac slept, for the
    /// limit of a day. See `JobPlanContext.wakesInLastDay`.
    var ledger: [TimeInterval] = []
    var history = JobHistory()
    /// The time of an alarm that can still be in the list of macOS. An
    /// app that starts with one takes it away or sets it again.
    var owedAlarm: TimeInterval?

    /// Without the alarms of more than a day ago, and without the ones
    /// from a time the clock has not reached: the clock was set back.
    mutating func prune(now: Date) {
        let time = now.timeIntervalSince1970
        ledger.removeAll { time - $0 >= Self.day || $0 > time + ManualHold.clockTolerance }
    }
}

/// The memory in UserDefaults, as one JSON value.
enum JobWakeMemoryStore {
    static let key = "JobWakeMemory"

    static func load(from defaults: UserDefaults) -> JobWakeMemory {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(JobWakeMemory.self, from: $0) } ?? JobWakeMemory()
    }

    static func save(_ memory: JobWakeMemory, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: key)
    }
}
