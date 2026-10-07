import Foundation

/// When a sample was taken: the date, and the seconds the Mac was awake
/// since boot (`CLOCK_UPTIME_RAW`). The second clock is missing in a test
/// and in a log of an older build.
struct SampleTime: Equatable {
    var at: Date
    var awake: TimeInterval?
}

extension EvidenceFrame {
    var time: SampleTime { SampleTime(at: at, awake: awake) }
}

/// A hole between two samples: the Mac slept, the sampling was stopped, or
/// the clock was set. The samples are 2 or 5 seconds apart, so 15 seconds
/// is no late timer.
///
/// Nothing was seen during the hole, so its time counts for no timer. The
/// collector takes the sample after it as a first sample, and the memory
/// of the rules moves by its length: an agent that worked before the sleep
/// is not released on the first sample after it, and a wait or a cap does
/// not run out while the Mac sleeps.
///
/// The timers of the rules run on the date. So the hole is what the date
/// moved without the Mac being awake for it: the date's step minus the
/// awake time. It is negative when the clock was set back, and the memory
/// then moves back with the clock. Without that, every timer would run
/// longer by the size of the step.
enum SampleGap {
    static let threshold: TimeInterval = 15
    /// The two clocks are read one after the other, and a time sync moves
    /// the date by a little all the time.
    static let clockTolerance: TimeInterval = 1

    /// The length of the hole before `now`, nil when there is none.
    static func length(from previous: SampleTime?, to now: SampleTime) -> TimeInterval? {
        guard let previous else { return nil }
        let wall = now.at.timeIntervalSince(previous.at)
        guard let before = previous.awake, let after = now.awake, after >= before else {
            return wall > threshold ? wall : nil
        }
        let awake = after - before
        var hole = wall - awake
        if abs(hole) <= clockTolerance { hole = 0 }
        // Awake and not sampled: the sampling was stopped.
        if awake > threshold { hole += awake }
        return hole == 0 ? nil : hole
    }

    /// The seconds between two samples with no hole between them.
    static func interval(from previous: SampleTime, to now: SampleTime) -> TimeInterval {
        if let before = previous.awake, let after = now.awake, after >= before { return after - before }
        return now.at.timeIntervalSince(previous.at)
    }

    static func awakeSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}

extension AgentMemory {
    /// The same memory, as if `gap` seconds had not passed.
    func shifted(by gap: TimeInterval) -> AgentMemory {
        var memory = self
        memory.firstSeenAt = firstSeenAt?.addingTimeInterval(gap)
        memory.lastCommandAt = lastCommandAt?.addingTimeInterval(gap)
        memory.lastBackgroundJobAt = lastBackgroundJobAt?.addingTimeInterval(gap)
        memory.lastAssertionAt = lastAssertionAt?.addingTimeInterval(gap)
        memory.lastFileWriteAt = lastFileWriteAt?.addingTimeInterval(gap)
        memory.lastCPUAt = lastCPUAt?.addingTimeInterval(gap)
        memory.weakOnlySince = weakOnlySince?.addingTimeInterval(gap)
        memory.lastReportSeenAt = lastReportSeenAt?.addingTimeInterval(gap)
        memory.hookWorkSince = hookWorkSince?.addingTimeInterval(gap)
        memory.workAfterHookIdleAt = workAfterHookIdleAt?.addingTimeInterval(gap)
        memory.approvalSignsSince = approvalSignsSince?.addingTimeInterval(gap)
        memory.cpuSamples = cpuSamples.map { CPUSample(at: $0.at.addingTimeInterval(gap), cpuSeconds: $0.cpuSeconds, interval: $0.interval) }
        return memory
    }
}

extension PolicyMemory {
    func shifted(by gap: TimeInterval) -> PolicyMemory {
        var memory = self
        memory.instances = instances.mapValues {
            Instance(lastWorkingAt: $0.lastWorkingAt?.addingTimeInterval(gap), waitingSince: $0.waitingSince?.addingTimeInterval(gap))
        }
        return memory
    }
}
