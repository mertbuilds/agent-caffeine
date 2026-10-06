import XCTest

private struct FakeError: Error {}

/// Holds the timeout until the test fires it, so no test waits.
private final class ManualTimer: @unchecked Sendable {
    private(set) var delays: [TimeInterval] = []
    private var work: [() -> Void] = []

    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        delays.append(delay)
        self.work.append(work)
    }

    func fire() {
        let due = work
        work = []
        due.forEach { $0() }
    }
}

/// What the call got from the connection, kept so the test can answer late.
private final class Held<T>: @unchecked Sendable {
    var answer: OneAnswer<T>?
}

final class HelperCallTests: XCTestCase {
    func testTheReplyAnswersTheCall() async throws {
        let timer = ManualTimer()
        let value: Bool = try await HelperCall.run(schedule: timer.schedule) { $0.give(.success(true)) }
        XCTAssertTrue(value)
        XCTAssertEqual(timer.delays, [HelperCall.timeout])
    }

    func testAnErrorAnswersTheCall() async {
        do {
            let _: Bool = try await HelperCall.run(schedule: ManualTimer().schedule) { $0.give(.failure(FakeError())) }
            XCTFail("the call did not throw")
        } catch {
            XCTAssertTrue(error is FakeError)
        }
    }

    /// A helper whose reply never comes.
    func testACallWithoutAnAnswerEndsAtTheTimeout() async {
        let timer = ManualTimer(), held = Held<Bool>()
        let started = expectation(description: "started"), timedOut = expectation(description: "timeout told")
        let call = Task {
            try await HelperCall.run(timeout: 3, schedule: timer.schedule, onTimeout: { timedOut.fulfill() }) { (answer: OneAnswer<Bool>) in
                held.answer = answer
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(timer.delays, [3])
        timer.fire()
        let result = await call.result
        XCTAssertEqual(result.failure as? HelperCallError, .timedOut)
        await fulfillment(of: [timedOut], timeout: 5)
        // The reply and the end of the connection come after all: both are dropped.
        XCTAssertEqual(held.answer?.give(.success(true)), false)
        XCTAssertEqual(held.answer?.give(.failure(HelperCallError.connectionLost)), false)
    }

    func testOnlyTheFirstAnswerCounts() async throws {
        let timer = ManualTimer(), held = Held<Int>()
        var timeouts = 0
        let value: Int = try await HelperCall.run(schedule: timer.schedule, onTimeout: { timeouts += 1 }) { answer in
            held.answer = answer
            XCTAssertTrue(answer.give(.success(1)))
            XCTAssertFalse(answer.give(.success(2)))
            XCTAssertFalse(answer.give(.failure(FakeError())))
        }
        XCTAssertEqual(value, 1)
        timer.fire()
        XCTAssertEqual(timeouts, 0, "A call that was answered has no timeout")
        XCTAssertEqual(held.answer?.give(.failure(HelperCallError.connectionLost)), false)
    }

    func testAnswersFromManyThreadsResumeOnce() async throws {
        for _ in 1...50 {
            let value: Int = try await HelperCall.run(schedule: ManualTimer().schedule) { answer in
                DispatchQueue.concurrentPerform(iterations: 8) { answer.give(.success($0)) }
            }
            XCTAssertTrue((0..<8).contains(value))
        }
    }

    func testAConnectionThatEndedIsToldFromOtherErrors() {
        XCTAssertTrue(HelperCall.isConnectionLoss(HelperCallError.connectionLost))
        XCTAssertTrue(HelperCall.isConnectionLoss(CocoaError(.xpcConnectionInterrupted)))
        XCTAssertTrue(HelperCall.isConnectionLoss(CocoaError(.xpcConnectionInvalid)))
        XCTAssertFalse(HelperCall.isConnectionLoss(HelperCallError.timedOut))
        XCTAssertFalse(HelperCall.isConnectionLoss(NSError(domain: NSCocoaErrorDomain, code: 4102)))
        XCTAssertFalse(HelperCall.isConnectionLoss(FakeError()))
    }

    func testTheErrorsReadAsOneSentence() {
        for error in [HelperCallError.timedOut, .connectionLost] {
            XCTAssertEqual(error.localizedDescription, "agent caffeine cannot reach its helper.")
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
