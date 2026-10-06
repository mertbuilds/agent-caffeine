import XCTest

final class LidDimmingTests: XCTestCase {
    /// A lid, a panel and a clock. Every step of the rules is carried out
    /// on the panel, as the controller does on the display.
    private struct Timeline {
        static let frame: TimeInterval = 1.0 / 60

        var now = Date(timeIntervalSince1970: 1_791_200_000)
        var memory = LidDimMemory()
        var inputs = LidDimInputs(holding: true)
        var panel: Float = 0.6
        var saved: Float?
        var slept = false
        var sleeps = 0
        var wakes = 0
        var writes = 0
        var notes: [String] = []
        var poll = LidPoll.slow

        @discardableResult
        mutating func feed(_ angle: Double?, after seconds: TimeInterval = Timeline.frame) -> LidDimStep {
            now = now.addingTimeInterval(seconds)
            inputs.angle = angle
            inputs.brightness = panel
            inputs.saved = saved
            inputs.slept = slept
            let step = LidDimming.decide(inputs, memory: memory, now: now)
            memory = step.memory
            notes += step.notes
            poll = step.poll
            for action in step.actions {
                switch action {
                case .save(let level): saved = level
                case .set(let level):
                    panel = level
                    writes += 1
                case .restore:
                    if let saved { panel = saved }
                    saved = nil
                case .sleepDisplays:
                    slept = true
                    sleeps += 1
                case .wakeDisplays:
                    slept = false
                    wakes += 1
                }
            }
            return step
        }

        /// The lid moves at an even speed, read 60 times a second.
        mutating func move(from: Double, to: Double, over seconds: TimeInterval) {
            let frames = max(Int((seconds / Timeline.frame).rounded()), 1)
            for frame in 1...frames {
                feed((from + (to - from) * Double(frame) / Double(frames)).rounded())
            }
        }

        mutating func rest(at angle: Double, for seconds: TimeInterval) {
            for _ in 0..<Int((seconds / Timeline.frame).rounded()) { feed(angle) }
        }
    }

    // MARK: The curve

    func testTheCurveAt45At30At15AndClosed() {
        XCTAssertEqual(LidDimming.curve(45), 1)
        XCTAssertEqual(LidDimming.curve(90), 1)
        XCTAssertEqual(LidDimming.curve(30), 0.708, accuracy: 0.001)
        XCTAssertEqual(LidDimming.curve(24), 0.5, accuracy: 0.001, "Half way is half the brightness")
        XCTAssertEqual(LidDimming.curve(15), 0.198, accuracy: 0.001)
        XCTAssertEqual(LidDimming.curve(LidDimming.closedAngle), 0)
        XCTAssertEqual(LidDimming.curve(0), 0)
    }

    func testTheCurveOnlyGoesUpWithTheAngle() {
        var before = -1.0
        for angle in stride(from: 0.0, through: 60, by: 0.5) {
            let value = LidDimming.curve(angle)
            XCTAssertGreaterThanOrEqual(value, before)
            if angle > LidDimming.closedAngle, angle <= LidDimming.fadeStart { XCTAssertGreaterThan(value, before, "at \(angle)") }
            before = value
        }
    }

    // MARK: Closing and opening

    func testAbove45NothingIsTouched() {
        var line = Timeline()
        line.move(from: 120, to: 45, over: 1)
        line.rest(at: 45, for: 3)
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
        XCTAssertEqual(line.memory.phase, .idle)
        XCTAssertEqual(line.writes, 0)
    }

    func testClosingFadesToZeroAndSleepsTheDisplays() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        XCTAssertEqual(line.panel, 0.6 * 0.708, accuracy: 0.01)
        XCTAssertEqual(line.saved, 0.6, "Saved before the first step down")
        line.move(from: 30, to: 15, over: 0.3)
        XCTAssertEqual(line.panel, 0.6 * 0.198, accuracy: 0.01)
        XCTAssertEqual(line.sleeps, 0)
        line.move(from: 15, to: 0, over: 0.3)
        XCTAssertEqual(line.panel, 0)
        XCTAssertEqual(line.sleeps, 1)
        XCTAssertEqual(line.memory.phase, .closed)
        line.rest(at: 0, for: 5)
        XCTAssertEqual(line.sleeps, 1, "Asked once. `DisplayRules` asks again when the display wakes under the lid")
        XCTAssertEqual(line.notes, [
            "the lid closes below 45 degrees: the built-in display fades",
            "the lid is shut: the built-in display is off",
        ])
    }

    func testTheBrightnessOnlyGoesDownWhileTheLidGoesDown() {
        var line = Timeline()
        line.feed(60)
        var before = line.panel
        for angle in stride(from: 59.0, through: 0, by: -1) {
            line.feed(angle)
            XCTAssertLessThanOrEqual(line.panel, before, "at \(angle)")
            before = line.panel
        }
    }

    func testOpeningIsTheSameCurveTheOtherWay() {
        var line = Timeline()
        line.feed(60)
        var down: [Double: Float] = [:]
        // At each degree the estimate of the angle gets time to arrive.
        for angle in stride(from: 59.0, through: 0, by: -1) {
            line.rest(at: angle, for: 0.3)
            down[angle] = line.panel
        }
        for angle in stride(from: 1.0, through: 59, by: 1) {
            line.rest(at: angle, for: 0.3)
            XCTAssertEqual(line.panel, down[angle] ?? -1, accuracy: 2 * LidDimming.minChange, "at \(angle)")
        }
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
        XCTAssertEqual(line.memory.phase, .idle)
        XCTAssertEqual(line.notes.last, "the lid is open at 45 degrees: the brightness is back")
    }

    func testOpeningWakesTheDisplaysAndLightsThemInTheSameStep() {
        var line = Timeline()
        line.move(from: 110, to: 0, over: 0.5)
        XCTAssertTrue(line.slept)
        line.rest(at: 0, for: 2)
        XCTAssertEqual(line.wakes, 0)
        let step = line.feed(6)
        XCTAssertEqual(step.actions.first, .wakeDisplays, "At the first reading above the closed angle")
        XCTAssertFalse(line.slept)
        XCTAssertGreaterThan(line.panel, 0, "And not black any more")
        XCTAssertLessThan(line.panel, 0.01, "From black, with no jump")
        line.rest(at: 12, for: 0.2)
        XCTAssertEqual(line.wakes, 1)
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(12)), accuracy: 0.01)
    }

    func testTheDisplaysAreNotWokenWhileTheLidSwitchSaysClosed() {
        var line = Timeline()
        line.move(from: 110, to: 0, over: 0.5)
        line.inputs.clamshellClosed = true
        line.rest(at: 5, for: 2)
        XCTAssertEqual(line.wakes, 0, "A sensor that reads 5 degrees for a shut lid")
        line.inputs.clamshellClosed = false
        line.feed(5)
        XCTAssertEqual(line.wakes, 1)
    }

    func testALidThatIsShutInOneStepGoesDarkInThatStep() {
        var line = Timeline()
        line.feed(110)
        let step = line.feed(0, after: 0.5)
        XCTAssertEqual(step.actions, [.save(0.6), .set(0), .sleepDisplays])
        XCTAssertEqual(step.target, 0)
    }

    func testNextToAnExternalDisplayTheDisplaysDoNotSleep() {
        var line = Timeline()
        line.inputs.externalDisplay = true
        line.move(from: 110, to: 0, over: 1)
        XCTAssertEqual(line.panel, 0)
        XCTAssertEqual(line.sleeps, 0)
        // The hold ends at the desk: dark until the lid opens.
        line.inputs.holding = false
        line.rest(at: 0, for: 3)
        XCTAssertEqual(line.panel, 0)
        line.move(from: 0, to: 60, over: 1)
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertEqual(line.wakes, 0)
    }

    func testTheUsersBrightnessIsTheOneFromWhenTheLidComesBelow45() {
        var line = Timeline()
        line.rest(at: 100, for: 1)
        // Auto-brightness, with the lid still up.
        line.panel = 0.4
        line.move(from: 100, to: 40, over: 0.5)
        XCTAssertEqual(line.saved, 0.4)
        line.move(from: 40, to: 60, over: 0.5)
        XCTAssertEqual(line.panel, 0.4)
    }

    func testSmallChangesAreNotWritten() {
        var line = Timeline()
        line.move(from: 60, to: 30, over: 1)
        line.rest(at: 30, for: 0.5)
        let writes = line.writes
        XCTAssertGreaterThan(writes, 15, "Many small steps, not one per degree")
        line.rest(at: 30, for: 0.5)
        XCTAssertEqual(line.writes, writes, "A lid that does not move writes nothing")
        XCTAssertEqual(LidDimming.minChange, 0.001)
    }

    // MARK: No steps

    /// What the eye saw as flicker: the brightness that one whole degree
    /// of the sensor is worth.
    func testOneDegreeOfTheSensorIsMoreThanThreePercentOfTheBrightness() {
        XCTAssertGreaterThan(LidDimming.curve(24.5) - LidDimming.curve(23.5), 0.035)
    }

    func testASlowCloseHasNoStepsTheEyeCanSee() {
        var line = Timeline()
        line.panel = 1
        line.feed(50)
        var largest: Float = 0
        var before = line.panel
        let frames = 5 * 120
        for frame in 1...frames {
            // 120 readings a second of a sensor that gives whole degrees.
            line.feed((50 - 50 * Double(frame) / Double(frames)).rounded(), after: 1.0 / 120)
            XCTAssertLessThanOrEqual(line.panel, before, "Never up while the lid goes down")
            largest = max(largest, before - line.panel)
            before = line.panel
        }
        XCTAssertEqual(line.panel, 0)
        XCTAssertLessThan(largest, 0.006, "One degree at once would be 0.036")
        XCTAssertGreaterThan(line.writes, 300)
    }

    func testOneDegreeOfNoiseWritesNothing() {
        var line = Timeline()
        line.move(from: 110, to: 15, over: 1)
        line.rest(at: 15, for: 0.5)
        let writes = line.writes
        for frame in 0..<240 { line.feed(frame % 2 == 0 ? 16 : 15) }
        XCTAssertEqual(line.writes, writes, "The sensor reads 15, 16, 15 for a lid that rests")
    }

    func testAFastCloseIsDarkWhenTheLidSwitchSaysClosed() {
        var line = Timeline()
        line.feed(60)
        line.move(from: 60, to: 8, over: 0.25)
        XCTAssertGreaterThan(line.panel, 0)
        line.inputs.clamshellClosed = true
        let step = line.feed(8)
        XCTAssertEqual(line.panel, 0, "The switch is first: the sensor still reads 8 degrees")
        XCTAssertEqual(step.target, 0)
        XCTAssertEqual(line.sleeps, 1)
        XCTAssertEqual(line.memory.phase, .closed)
        // It opens: from black, with no jump.
        line.inputs.clamshellClosed = false
        line.feed(8)
        XCTAssertLessThan(line.panel, 0.01)
        line.rest(at: 8, for: 0.5)
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(8)), accuracy: 0.002)
    }

    func testALidThatIsShutInALittleTimeIsDarkAtTheClosedAngle() {
        var line = Timeline()
        line.feed(60)
        line.move(from: 60, to: 3, over: 0.3)
        XCTAssertEqual(line.panel, 0, "The estimate may be behind. The closed angle is not")
    }

    func testALidThatComesDownBetweenTwoSlowReadingsFadesAndDoesNotJump() {
        var line = Timeline()
        line.feed(110)
        line.feed(25, after: 0.5)
        XCTAssertGreaterThan(line.panel, 0.5, "Not at the brightness of 25 degrees in one step")
        XCTAssertEqual(line.poll, .fast)
        line.rest(at: 25, for: 0.5)
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(25)), accuracy: 0.002)
    }

    // MARK: A lid that rests half open

    func testALidThatRestsAt30DegreesIsBrightAgainAfterOneAndAHalfSeconds() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        line.rest(at: 30, for: 1.4)
        XCTAssertEqual(line.panel, 0.6 * 0.708, accuracy: 0.01, "Still on the curve")
        line.rest(at: 30, for: 0.5)
        XCTAssertEqual(line.panel, 0.6, accuracy: LidDimming.minChange)
        XCTAssertEqual(line.saved, 0.6, "Saved until the lid is up again")
        XCTAssertEqual(line.notes.last, "the lid rests at 30 degrees: the brightness is back")
        // It moves down again: back on the curve in a moment, no jump.
        line.feed(29)
        XCTAssertGreaterThan(line.panel, 0.5)
        line.move(from: 29, to: 25, over: 0.3)
        line.rest(at: 25, for: 0.1)
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(25)), accuracy: 0.01)
    }

    func testOneDegreeOfNoiseDoesNotStopTheRest() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        for frame in 0..<120 { line.feed(frame % 2 == 0 ? 30 : 31) }
        XCTAssertEqual(line.panel, 0.6, accuracy: LidDimming.minChange)
    }

    func testALidThatRestsBelow20DegreesStaysDim() {
        var line = Timeline()
        line.move(from: 110, to: 15, over: 1)
        line.rest(at: 15, for: 10)
        XCTAssertEqual(line.panel, 0.6 * 0.198, accuracy: 0.01)
    }

    func testALidThatClosesVerySlowlyDoesNotCountAsResting() {
        var line = Timeline()
        line.feed(46)
        for angle in stride(from: 45.0, through: 21, by: -1) { line.rest(at: angle, for: 1) }
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(21)), accuracy: 0.01)
    }

    func testALidThatWasNotSeenComingDownIsLeftAlone() {
        var line = Timeline()
        line.rest(at: 30, for: 3)
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
        line.move(from: 30, to: 20, over: 0.5)
        line.rest(at: 20, for: 0.1)
        XCTAssertEqual(line.panel, 0.6 * Float(LidDimming.curve(20)), accuracy: 0.01, "It moves down: it fades")
    }

    // MARK: Not fighting the user

    func testABrightnessKeyWithTheLidHalfOpenGivesTheNewUserValue() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        line.rest(at: 30, for: 2)
        line.panel = 0.8
        line.rest(at: 30, for: 1)
        XCTAssertEqual(line.panel, 0.8, "Not put back")
        XCTAssertEqual(line.saved ?? -1, 0.8, accuracy: 0.001)
        line.move(from: 30, to: 60, over: 0.5)
        XCTAssertEqual(line.panel, 0.8, accuracy: 0.001)
    }

    func testAChangeOnADimDisplayIsNotUndoneAndIsNotTheUsers() {
        var line = Timeline()
        line.move(from: 110, to: 15, over: 1)
        line.rest(at: 15, for: 1)
        let dim = line.panel
        line.panel = dim + 0.06
        line.rest(at: 15, for: 1)
        XCTAssertEqual(line.panel, dim + 0.06, "A lid that rests writes nothing")
        XCTAssertEqual(line.saved, 0.6, "Below 20 degrees nobody reads the display: the value from 45 degrees stays")
        line.move(from: 15, to: 60, over: 0.5)
        XCTAssertEqual(line.panel, 0.6)
    }

    /// Auto-brightness: the lid covers the light sensor, and macOS makes
    /// the display darker a little at a time.
    func testADriftWhileTheLidPausesIsNotTakenForTheUsers() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        for _ in 0..<30 {
            line.panel -= 0.004
            line.feed(30)
        }
        line.move(from: 30, to: 18, over: 0.5)
        for _ in 0..<60 {
            line.panel = max(line.panel - 0.002, 0.01)
            line.feed(18)
        }
        XCTAssertEqual(line.saved, 0.6)
        line.move(from: 18, to: 60, over: 0.5)
        XCTAssertEqual(line.panel, 0.6)
    }

    func testADriftWithTheLidAtRestIsNotTheUsersAndAKeyAfterItIs() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        line.rest(at: 30, for: 2.5)
        XCTAssertEqual(line.panel, 0.6, accuracy: LidDimming.minChange)
        for _ in 0..<50 {
            line.panel -= 0.002
            line.feed(30)
        }
        XCTAssertEqual(line.saved, 0.6, "Ten percent, a little at a time")
        XCTAssertEqual(line.panel, 0.5, accuracy: 0.002, "And not fought")
        line.panel += 0.0625
        line.rest(at: 30, for: 0.5)
        XCTAssertEqual(line.saved ?? -1, 0.5625, accuracy: 0.002, "One press of the key")
    }

    func testAChangeWhileTheLidMovesIsNotTakenForTheUsers() {
        var line = Timeline()
        line.move(from: 110, to: 30, over: 1)
        // macOS moves the brightness a little while the lid goes down.
        line.panel -= 0.1
        line.move(from: 30, to: 25, over: 0.2)
        XCTAssertEqual(line.saved, 0.6)
    }

    // MARK: When it does nothing, and when it gives up

    func testWithoutASensorNothingHappens() {
        var line = Timeline()
        line.inputs.sensorAvailable = false
        for angle: Double? in [110, 30, 0, nil, 30] { XCTAssertEqual(line.feed(angle).actions, []) }
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertEqual(line.memory.phase, .idle)
    }

    func testWithTheSettingOffNothingHappensAndAFadeEnds() {
        var line = Timeline()
        line.inputs.enabled = false
        line.move(from: 110, to: 0, over: 1)
        XCTAssertEqual(line.panel, 0.6)
        line.inputs.enabled = true
        line.feed(110)
        line.move(from: 110, to: 20, over: 1)
        XCTAssertLessThan(line.panel, 0.3)
        line.inputs.enabled = false
        let step = line.feed(20)
        XCTAssertEqual(step.actions, [.restore(reason: "the setting is off")])
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
    }

    func testWhileAgentCaffeineDoesNotHoldNoFadeStarts() {
        var line = Timeline()
        line.inputs.holding = false
        line.move(from: 110, to: 0, over: 1)
        line.rest(at: 0, for: 2)
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertEqual(line.sleeps, 0)
        XCTAssertNil(line.saved)
    }

    func testAHoldThatEndsHalfWayStillOpensTheSameWay() {
        var line = Timeline()
        line.move(from: 110, to: 10, over: 1)
        line.inputs.holding = false
        line.move(from: 10, to: 30, over: 0.3)
        XCTAssertEqual(line.panel, 0.6 * 0.708, accuracy: 0.01)
        line.move(from: 30, to: 50, over: 0.3)
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
    }

    func testAHoldThatEndsUnderTheShutLidGivesTheBrightnessBack() {
        var line = Timeline()
        line.move(from: 110, to: 0, over: 1)
        line.inputs.holding = false
        let step = line.feed(0)
        XCTAssertEqual(step.actions, [.restore(reason: "agent caffeine no longer keeps the Mac awake")])
        XCTAssertEqual(line.panel, 0.6, "The Mac goes to sleep and wakes with its own brightness")
        XCTAssertEqual(line.memory.phase, .idle)
    }

    func testASensorThatStopsAnsweringGivesTheBrightnessBack() {
        var line = Timeline()
        line.move(from: 110, to: 20, over: 1)
        let dim = line.panel
        // The sensor was asked slowly: the first answer that is missing
        // comes half a second after the last answer.
        line.feed(nil, after: 0.5)
        line.feed(nil, after: 0.2)
        line.feed(nil, after: 0.2)
        XCTAssertEqual(line.panel, dim, "Not yet: an answer can be late")
        XCTAssertEqual(line.poll, .fast)
        let step = line.feed(nil, after: 0.1)
        XCTAssertEqual(step.actions, [.restore(reason: "the lid angle sensor stopped answering")])
        XCTAssertEqual(line.panel, 0.6)
        XCTAssertNil(line.saved)
        // It answers again with the lid as it was: left alone.
        line.rest(at: 20, for: 3)
        XCTAssertEqual(line.panel, 0.6)
    }

    func testOneAnswerThatIsLateChangesNothing() {
        var line = Timeline()
        line.move(from: 110, to: 20, over: 1)
        line.rest(at: 20, for: 0.3)
        let dim = line.panel
        XCTAssertEqual(line.feed(nil, after: 0.5).actions, [])
        line.rest(at: 20, for: 0.2)
        XCTAssertEqual(line.feed(nil, after: 0.4).actions, [], "Counted from the first answer that is missing, each time")
        XCTAssertEqual(line.panel, dim)
        XCTAssertEqual(line.saved, 0.6)
        XCTAssertEqual(LidDimming.sensorTimeout, 0.5)
    }

    func testASensorThatStopsUnderTheClosedLidLeavesTheDisplayDark() {
        var line = Timeline()
        line.move(from: 110, to: 0, over: 1)
        line.inputs.clamshellClosed = true
        line.feed(nil, after: 0.5)
        let step = line.feed(nil, after: 0.5)
        XCTAssertEqual(step.actions, [], "`DisplayRules` goes on, and puts the brightness back when the lid opens")
        XCTAssertEqual(line.panel, 0)
        XCTAssertEqual(line.saved, 0.6)
        XCTAssertEqual(line.memory.phase, .idle)
    }

    func testADisplayThatIsDarkAlreadyIsNotTouched() {
        var line = Timeline()
        line.panel = 0
        line.move(from: 110, to: 0, over: 1)
        XCTAssertNil(line.saved)
        XCTAssertEqual(line.writes, 0)
    }

    func testAValueThatWasSavedBeforeIsTheUsersBrightness() {
        var line = Timeline()
        // `DisplayRules` made the display dark under the closed lid.
        line.panel = 0
        line.saved = 0.7
        line.feed(0)
        XCTAssertEqual(line.memory.phase, .closed)
        line.move(from: 0, to: 50, over: 0.5)
        XCTAssertEqual(line.panel, 0.7)
    }

    // MARK: How often the sensor is asked

    func testTheSensorIsAskedFastOnlyBelow70DegreesWhileTheLidMoves() {
        var line = Timeline()
        line.feed(120)
        line.feed(100)
        XCTAssertEqual(line.poll, .slow, "Wide open: slow, also while it moves")
        line.feed(69, after: 0.5)
        XCTAssertEqual(line.poll, .fast)
        line.rest(at: 69, for: 1.9)
        XCTAssertEqual(line.poll, .fast)
        line.rest(at: 69, for: 0.2)
        XCTAssertEqual(line.poll, .slow, "Steady for 2 seconds")
        line.feed(40, after: 0.5)
        XCTAssertEqual(line.poll, .fast)
        line.rest(at: 40, for: 1.6)
        XCTAssertEqual(line.poll, .fast, "The brightness is on its way back")
        line.rest(at: 40, for: 1)
        XCTAssertEqual(line.poll, .slow)
        XCTAssertEqual(LidPoll.slow.interval, 0.5)
        XCTAssertEqual(LidPoll.fast.interval, 1.0 / 120, "The refresh rate of the display")
    }
}
