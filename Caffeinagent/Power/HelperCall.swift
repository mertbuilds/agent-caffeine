import Foundation

/// Why a call to the helper got no answer.
enum HelperCallError: LocalizedError, Equatable {
    case timedOut
    case connectionLost

    var errorDescription: String? {
        "agent caffeine cannot reach its helper."
    }
}

/// One answer for one call. The reply, the error handler, the end of the
/// connection and the timeout can all come, each on its own thread: the
/// first one counts and the rest is dropped.
final class OneAnswer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// False when the call was answered before.
    @discardableResult
    func give(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: result)
        return waiting != nil
    }
}

enum HelperCall {
    /// The helper answers in a fraction of a second. A set that the kernel
    /// does not confirm takes it up to four seconds.
    static let timeout: TimeInterval = 5

    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void

    static let afterDelay: Schedule = { delay, work in
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Runs `start` and waits for its answer, for `timeout` seconds at
    /// most, so a helper that hangs never hangs the caller.
    /// - Parameter onTimeout: runs when the timeout was the answer.
    static func run<T>(
        timeout: TimeInterval = HelperCall.timeout,
        schedule: Schedule = afterDelay,
        onTimeout: @escaping () -> Void = {},
        _ start: (OneAnswer<T>) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let answer = OneAnswer(continuation)
            schedule(timeout) {
                if answer.give(.failure(HelperCallError.timedOut)) { onTimeout() }
            }
            start(answer)
        }
    }

    /// The helper went away while the call was under way, or before it.
    /// launchd starts it again on the next call, so one more try is worth it.
    static func isConnectionLoss(_ error: Error) -> Bool {
        if let error = error as? HelperCallError { return error == .connectionLost }
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && [NSXPCConnectionInterrupted, NSXPCConnectionInvalid].contains(error.code)
    }
}
