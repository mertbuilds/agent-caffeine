import XCTest

final class WakeGateTests: XCTestCase {
    func testOpenUntilMacOSSaysTheMacGoesToSleep() {
        var gate = WakeGate()
        XCTAssertTrue(gate.allowsHold(holding: false))
        // A sleep with no word of it: the gate has nothing to hold back.
        gate.sampled(awake: 10, slept: true)
        XCTAssertTrue(gate.allowsHold(holding: false))
        // A wake with no sleep before it changes nothing.
        gate.didWake(awake: 20)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }

    func testAfterTheWordOfSleepNoHoldStartsAndARunningOneGoesOn() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertTrue(gate.allowsHold(holding: true))
        // Samples with no sleep: the Mac stays awake under the hold.
        for second in 0...100 { gate.sampled(awake: TimeInterval(second), slept: false) }
        XCTAssertTrue(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
    }

    func testASleepAfterTheWordOfSleepEndsARunningHold() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        gate.sampled(awake: 10, slept: true)
        XCTAssertFalse(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
        // The Mac wakes by itself again and again.
        gate.sampled(awake: 12, slept: false)
        gate.sampled(awake: 14, slept: true)
        XCTAssertFalse(gate.allowsHold(holding: true))
    }

    func testAFullWakeOpensTheGateWithTheFirstSampleAfterIt() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        gate.sampled(awake: 10, slept: true)
        gate.didWake(awake: 20)
        XCTAssertFalse(gate.allowsHold(holding: false), "Not before a sample from after the wake")
        // A sample that was taken before the wake and arrives after it.
        XCTAssertFalse(gate.sampled(awake: 19.9, slept: false))
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertTrue(gate.sampled(awake: 20.2, slept: true))
        XCTAssertTrue(gate.allowsHold(holding: false), "The sleep before this sample is the one that is over")
        XCTAssertEqual(gate, WakeGate())
    }

    func testAWakeBeforeAnySampleKeepsARunningHoldUntilTheSample() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        gate.didWake(awake: 20)
        XCTAssertTrue(gate.allowsHold(holding: true))
        XCTAssertFalse(gate.allowsHold(holding: false))
        gate.sampled(awake: 20, slept: true)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }

    func testTheNextSleepClosesTheGateAgain() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        gate.didWake(awake: 20)
        gate.willSleep(awake: 25)
        gate.sampled(awake: 30, slept: false)
        XCTAssertFalse(gate.allowsHold(holding: false), "The sample came after the word of the second sleep")
        gate.didWake(awake: 40)
        gate.sampled(awake: 41, slept: false)
        XCTAssertTrue(gate.allowsHold(holding: false))
    }

    // MARK: Awake with the display off

    /// The Mac wakes with the display off and stays awake: no word of a
    /// wake comes. After `steadyAwake` with no sleep this is no dark wake.
    func testAwakeForLongWithNoSleepOpensTheGate() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        XCTAssertFalse(gate.sampled(awake: 1000, slept: true))
        XCTAssertFalse(gate.sampled(awake: 1000 + WakeGate.steadyAwake, slept: false), "Not at the limit, only after it")
        XCTAssertFalse(gate.allowsHold(holding: false))
        XCTAssertTrue(gate.sampled(awake: 1002 + WakeGate.steadyAwake, slept: false), "It opens as a full wake does")
        XCTAssertTrue(gate.allowsHold(holding: false))
        XCTAssertEqual(gate, WakeGate())
    }

    func testEverySleepStartsTheStretchAgain() {
        var gate = WakeGate()
        gate.willSleep(awake: 0)
        // Dark wakes of 45 seconds, again and again.
        var awake: TimeInterval = 0
        for _ in 0..<20 {
            XCTAssertFalse(gate.sampled(awake: awake, slept: true))
            for _ in 0..<9 {
                awake += 5
                XCTAssertFalse(gate.sampled(awake: awake, slept: false))
            }
        }
        XCTAssertFalse(gate.allowsHold(holding: false))
    }

    /// The word of sleep came and the Mac did not sleep: lid closed on
    /// wall power under a hold. After `steadyAwake` the word is forgotten.
    func testTheWordOfSleepIsForgottenWhenNoSleepFollows() {
        var gate = WakeGate()
        gate.willSleep(awake: 50)
        XCTAssertFalse(gate.sampled(awake: 50 + WakeGate.steadyAwake, slept: false))
        XCTAssertTrue(gate.sampled(awake: 52 + WakeGate.steadyAwake, slept: false))
        XCTAssertEqual(gate, WakeGate())
    }
}
