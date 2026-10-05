import Foundation

/// A hole between two samples: the Mac slept, or the sampling was stopped.
/// The samples are 2 or 5 seconds apart, so 15 seconds is no late timer.
///
/// Nothing was seen during the hole, so its time counts for no timer. The
/// collector takes the sample after it as a first sample, and the memory
/// of the rules moves forward by its length: an agent that worked before
/// the sleep is not released on the first sample after it, and a wait or
/// a cap does not run out while the Mac sleeps.
enum SampleGap {
    static let threshold: TimeInterval = 15

    /// The length of the hole before `now`, nil when there is none.
    static func length(from previous: Date?, to now: Date) -> TimeInterval? {
        guard let previous else { return nil }
        let gap = now.timeIntervalSince(previous)
        return gap > threshold ? gap : nil
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
