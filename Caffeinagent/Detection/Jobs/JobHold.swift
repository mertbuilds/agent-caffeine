import Foundation

/// A hold for one run of a scheduled job the user switched on. It opens
/// at the time of the alarm, a lead time before the job, and it is
/// evidence of work like a `ManualHold`: `HoldPolicy` decides what it is
/// worth, so every stop still wins.
///
/// A hold never makes itself longer. It ends at the first of these:
///
/// - The job was seen to run and is gone. The caller looks at the
///   processes and says what it saw, see `observe`.
/// - The start grace after the time of the job, when the job was never
///   seen to run.
/// - The cap after the hold opened. The job itself runs on.
///
/// A job that an agent runs (Hermes) is not watched here. Its hold is a
/// bridge from the alarm to the start grace, and from the moment the
/// agent works the detection engine holds the Mac by its own rules.
struct JobHold: Codable, Equatable, Identifiable {
    /// No job holds for longer, whatever the settings say.
    static let capLimit: TimeInterval = 2 * 3600

    enum State: Equatable {
        /// Before the alarm.
        case notOpen
        /// Open, and the job was not seen yet.
        case waiting
        case running
        /// The job was seen to run and to end.
        case ended
        /// The start grace passed and the job was never seen.
        case neverStarted
        /// The job still ran at the cap.
        case cutAtCap
        /// The bridge for an agent job is over. The detection engine
        /// says if the agent works.
        case bridgeOver
    }

    /// The id of the job and the time of the run.
    var id: String
    var jobID: String
    var source: ScheduledJob.Source
    /// The name of the job. See `ScheduledJob.name` for what it can hold.
    var name: String
    /// The time of the alarm, in seconds since the epoch.
    var start: TimeInterval
    /// The time of the job.
    var fireAt: TimeInterval
    var startGrace: TimeInterval
    var cap: TimeInterval
    /// When the job was first seen to run.
    var seenAt: TimeInterval?
    /// When a job that was seen to run was seen to be gone.
    var endedAt: TimeInterval?

    /// Nil for a job the user did not switch on.
    static func open(job: ScheduledJob, fireAt: Date, settings: JobSettings) -> JobHold? {
        guard job.enabled else { return nil }
        let fire = fireAt.timeIntervalSince1970
        return JobHold(
            id: "\(job.id)@\(Int(fire))", jobID: job.id, source: job.source, name: job.name,
            start: fire - settings.leadTime, fireAt: fire,
            startGrace: job.source == .hermes ? JobSettings.agentStartGrace : settings.startGrace,
            cap: min(settings.holdCap, capLimit)
        )
    }

    /// True for a job whose process the caller looks for.
    var isWatched: Bool { source != .hermes }

    /// When the hold is over, as far as is known now.
    var end: TimeInterval {
        if let endedAt { return endedAt }
        let hardEnd = start + cap
        if isWatched, seenAt != nil { return hardEnd }
        return min(fireAt + startGrace, hardEnd)
    }

    var endsAt: Date { Date(timeIntervalSince1970: end) }
    var startedAt: Date { Date(timeIntervalSince1970: start) }

    /// The title of its line in the menu.
    var title: String { name }
    /// What the Mac is awake for, for the headline: "Awake for backup.sh".
    var subject: String { name }

    /// The time alone: the hold is open and not over. A clock that was
    /// set back to before the alarm closes it.
    func isTimely(now: Date) -> Bool {
        let time = now.timeIntervalSince1970
        guard start.isFinite, fireAt.isFinite, startGrace.isFinite, cap.isFinite, cap > 0, cap <= Self.capLimit, start <= fireAt else { return false }
        return time >= start && time < end
    }

    /// What the caller saw of the job at `now`. A job that runs keeps the
    /// hold open up to the cap, and a job that ran and is gone ends it.
    /// Nothing changes a hold that is not open: one that is over stays
    /// over, also when the job starts late.
    mutating func observe(running: Bool, now: Date) {
        guard isWatched, isTimely(now: now) else { return }
        let time = now.timeIntervalSince1970
        if running {
            seenAt = seenAt ?? time
        } else if seenAt != nil {
            endedAt = time
        }
    }

    func state(now: Date) -> State {
        let time = now.timeIntervalSince1970
        if endedAt != nil { return .ended }
        if time < start { return .notOpen }
        if time < end { return seenAt != nil ? .running : .waiting }
        guard isWatched else { return .bridgeOver }
        return seenAt != nil ? .cutAtCap : .neverStarted
    }
}
