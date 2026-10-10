import Foundation

/// What the user chose for "Wake for jobs".
struct JobSettings: Codable, Equatable {
    /// The switch of the feature. Off: no alarm is set and no job holds.
    var wakeForJobs = false
    /// The Mac is woken for a job only while it is on power. A Mac in a
    /// bag does not wake itself then.
    var onPowerOnly = true
    /// How long before a job the Mac is woken, so the disk and the
    /// network are ready when the job starts.
    var leadTime: TimeInterval = 60
    /// No more alarms than this in 24 hours.
    var maxWakesPerDay = 12
    /// How long the Mac stays awake after the time of a job that was not
    /// seen to start.
    var startGrace: TimeInterval = 240
    /// The longest time one job keeps the Mac awake.
    var holdCap: TimeInterval = 1800
    /// By `ScheduledJob.id`. A job with no entry is off: nothing is
    /// adopted by itself.
    var jobSwitches: [String: Bool] = [:]

    init() {}

    static let leadTimeRange: ClosedRange<TimeInterval> = 30...1800
    /// The helper refuses more than 48 alarms a day.
    static let maxWakesRange = 1...48
    static let startGraceRange: ClosedRange<TimeInterval> = 60...1800
    static let holdCapRange: ClosedRange<TimeInterval> = 300...7200

    /// A job that runs more often than this on average is not offered.
    static let minimumGap: TimeInterval = 1800
    /// While the Mac is awake, a job that runs within this time needs no
    /// new alarm: the alarm of an awake Mac does nothing, and a new plan
    /// is made when the Mac is about to sleep. An alarm that is set stays.
    static let nearWindow: TimeInterval = 1800
    /// No alarm on battery at the battery floor plus this or below: a
    /// stop cannot undo a wake.
    static let batteryMargin = 5
    /// The helper takes no alarm that is closer than this.
    static let minimumAhead: TimeInterval = 30
    /// The start grace of a job that an agent runs. The detection engine
    /// holds the Mac from the moment the agent works.
    static let agentStartGrace: TimeInterval = 300

    func isOn(_ jobID: String) -> Bool {
        jobSwitches[jobID] ?? false
    }

    mutating func set(_ on: Bool, for jobID: String) {
        jobSwitches[jobID] = on ? true : nil
    }

    /// The jobs with the switches of the user. A job that is listed
    /// with no switch is off, whatever is stored for its id.
    func applied(to jobs: [ScheduledJob]) -> [ScheduledJob] {
        jobs.map { job in
            var job = job
            job.enabled = job.noSwitch == nil && isOn(job.id)
            return job
        }
    }

    /// The settings without the switches of the jobs that are listed
    /// with no switch (`ScheduledJob.noSwitch`). The id of such a job can
    /// belong to another line tomorrow, and a switch that was kept would
    /// then be on for a job the user never switched on.
    func withoutSwitches(ofUnclear jobs: [ScheduledJob]) -> JobSettings {
        var next = self
        for job in jobs where job.noSwitch != nil { next.jobSwitches[job.id] = nil }
        return next
    }

    private enum CodingKeys: String, CodingKey {
        case wakeForJobs, onPowerOnly, leadTime, maxWakesPerDay, startGrace, holdCap, jobSwitches
    }

    /// A key that is missing keeps its default, and so does a key whose
    /// value is of the wrong type: one value that cannot be read does not
    /// cost the other settings. A number out of its range is cut to the
    /// range.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = JobSettings()
        func value<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        func time(_ key: CodingKeys, _ fallback: TimeInterval, _ range: ClosedRange<TimeInterval>) -> TimeInterval {
            let value = value(key, fallback)
            guard value.isFinite else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        wakeForJobs = value(.wakeForJobs, defaults.wakeForJobs)
        onPowerOnly = value(.onPowerOnly, defaults.onPowerOnly)
        leadTime = time(.leadTime, defaults.leadTime, Self.leadTimeRange)
        let wakes = value(.maxWakesPerDay, defaults.maxWakesPerDay)
        maxWakesPerDay = min(max(wakes, Self.maxWakesRange.lowerBound), Self.maxWakesRange.upperBound)
        startGrace = time(.startGrace, defaults.startGrace, Self.startGraceRange)
        holdCap = time(.holdCap, defaults.holdCap, Self.holdCapRange)
        jobSwitches = value(.jobSwitches, [String: Bool]()).filter(\.value)
    }
}

/// The settings of "Wake for jobs" in UserDefaults, as one JSON value.
enum JobSettingsStore {
    static let key = "JobSettings"

    /// Settings that cannot be read give the defaults: the feature off
    /// and every job off.
    static func load(from defaults: UserDefaults) -> JobSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(JobSettings.self, from: $0) } ?? JobSettings()
    }

    static func save(_ settings: JobSettings, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
