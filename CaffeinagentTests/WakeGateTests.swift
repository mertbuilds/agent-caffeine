import XCTest

final class WakeGateTests: XCTestCase {
    func testOpenUntilMacOSSaysTheMacGoesToSleep() {
        var gate = WakeGate()
        XCTAssertTrue(gate.allowsHold(holding: false))
        // A hole with no word of sleep: the sampling was stopped, or the clock was set.
        gate.sampled(awake: 10, gap: true)
        XCTAssertTrue(gate.allowsHold(holding: false))
        // A wake with no sleep before it changes nothing.
        gate.didWake(awake: 20)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }

    func testAfterTheWordOfSleepNoHoldStartsAndARunningOneGoesOn() {
        var gate = WakeGate()
        gate.willSleep()
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertTrue(gate.allowsHold(holding: true))
        // Samples with no hole: the Mac stays awake under the hold.
        for second in 0..<100 { gate.sampled(awake: TimeInterval(second), gap: false) }
        XCTAssertTrue(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
    }

    func testAHoleAfterTheWordOfSleepEndsARunningHold() {
        var gate = WakeGate()
        gate.willSleep()
        gate.sampled(awake: 10, gap: true)
        XCTAssertFalse(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
        // The Mac wakes by itself again and again.
        gate.sampled(awake: 12, gap: false)
        gate.sampled(awake: 14, gap: true)
        XCTAssertFalse(gate.allowsHold(holding: true))
    }

    func testAFullWakeOpensTheGateWithTheFirstSampleAfterIt() {
        var gate = WakeGate()
        gate.willSleep()
        gate.sampled(awake: 10, gap: true)
        gate.didWake(awake: 20)
        XCTAssertFalse(gate.allowsHold(holding: false), "Not before a sample from after the wake")
        // A sample that was taken before the wake and arrives after it.
        XCTAssertFalse(gate.sampled(awake: 19.9, gap: false))
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertTrue(gate.sampled(awake: 20.2, gap: true))
        XCTAssertTrue(gate.allowsHold(holding: false), "The hole before this sample is the sleep that is over")
        XCTAssertEqual(gate, WakeGate())
    }

    func testAWakeBeforeAnySampleKeepsARunningHoldUntilTheSample() {
        var gate = WakeGate()
        gate.willSleep()
        gate.didWake(awake: 20)
        XCTAssertTrue(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
        gate.sampled(awake: nil, gap: true)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }

    func testTheNextSleepClosesTheGateAgain() {
        var gate = WakeGate()
        gate.willSleep()
        gate.didWake(awake: 20)
        gate.willSleep()
        gate.sampled(awake: 30, gap: false)
        XCTAssertFalse(gate.allowsHold(holding: false), "The sample came after the word of the second sleep")
        gate.didWake(awake: 40)
        gate.sampled(awake: 41, gap: false)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }
}
