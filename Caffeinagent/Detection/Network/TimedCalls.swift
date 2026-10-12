import Foundation

/// Runs calls into macOS that have no time limit of their own, each
/// with one: reading the name of the Wi-Fi, a scan, a join, a read of
/// the Keychain. The caller waits for at most the limit, so one call
/// that macOS never answers cannot hold the work of the hotspot for
/// good. Such a call counts as a failed try.
///
/// One call runs at a time. While an earlier one still hangs, the next
/// is not started and fails at once.
final class TimedCalls: @unchecked Sendable {
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var busy = false

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .utility, attributes: .concurrent)
    }

    /// Nil when the time ran out, and when an earlier call still hangs.
    func run<Value>(_ seconds: TimeInterval, _ work: @escaping () -> Value) -> Value? {
        lock.lock()
        guard !busy else {
            lock.unlock()
            return nil
        }
        busy = true
        lock.unlock()
        let done = DispatchSemaphore(value: 0)
        var value: Value?
        queue.async { [self] in
            let result = work()
            lock.lock()
            value = result
            busy = false
            lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
