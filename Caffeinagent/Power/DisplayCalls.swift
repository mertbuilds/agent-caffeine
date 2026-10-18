import Foundation
import os

/// Runs the calls that reach the displays (the brightness through
/// DisplayServices and IOKit, display sleep and its `pmset` fallback) on a
/// serial queue of their own, one at a time and in order. A call that takes
/// longer than 200 ms turns the display feature off for this run of the app:
/// no call is made after it. So the main thread waits for a call that hangs
/// once and for 200 ms at most, and the samples and the heartbeats of the
/// helper go on.
final class DisplayCalls {
    static let limit: TimeInterval = 0.2

    private let queue = DispatchQueue(label: "com.caffeinagent.app.display-calls", qos: .userInitiated)
    private let limit: TimeInterval
    private let log = Logger(subsystem: "com.caffeinagent.app", category: "Display")
    /// Set and read on the main thread only.
    private(set) var isOff = false

    init(limit: TimeInterval = DisplayCalls.limit) {
        self.limit = limit
    }

    /// Nil when the feature is off, and when this call took too long.
    func run<T>(_ name: String, _ work: @escaping () -> T) -> T? {
        guard !isOff else { return nil }
        let result = Box<T>()
        let done = DispatchSemaphore(value: 0)
        queue.async {
            result.value = work()
            done.signal()
        }
        guard done.wait(timeout: .now() + limit) == .success else {
            isOff = true
            log.error("\(name, privacy: .public) took longer than \(Int(self.limit * 1000)) ms: the display feature is off until Agent Caffeine starts again")
            return nil
        }
        return result.value
    }

    /// Written on the queue, read after the semaphore.
    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }
}
