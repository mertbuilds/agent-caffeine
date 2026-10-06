import XCTest

final class LidAngleEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    /// The same numbers on every run.
    private struct Dice {
        var state: UInt64 = 7

        /// 0 to 1.
        mutating func roll() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    private struct Run {
        /// The largest change of the share of the brightness in one frame.
        var largestStep = 0.0
        /// How often the brightness went up.
        var turns = 0
        var angles: [Double] = []
    }

    /// A lid that goes from 60 degrees down at an even speed, half a
    /// second after the start. The sensor takes a reading of its own at
    /// uneven times and gives whole degrees. It is asked once per frame,
    /// by a timer that is a little early or late.
    private func close(
        fadeSeconds: Double, hz: Double = 120, sensor: ClosedRange<Double> = 0.005...0.012, stopAt: Double = 0, extra: Double = 1
    ) -> Run {
        var dice = Dice()
        var estimator = LidAngleEstimator()
        let speed = 42 / fadeSeconds
        func truth(_ time: Double) -> Double { max(60 - speed * max(time - 0.5, 0), stopAt) }
        var run = Run()
        var time = 0.0
        var nextReading = 0.0
        var reported = 60.0
        var before = LidDimming.curve(60)
        while time < 0.5 + (60 - stopAt) / speed + extra {
            time += 1 / hz + (dice.roll() - 0.5) * 0.002
            while nextReading <= time {
                reported = truth(nextReading).rounded()
                nextReading += sensor.lowerBound + dice.roll() * (sensor.upperBound - sensor.lowerBound)
            }
            let angle = estimator.update(sample: reported, now: start.addingTimeInterval(time))
            let share = LidDimming.curve(angle)
            run.largestStep = max(run.largestStep, abs(share - before))
            if share > before { run.turns += 1 }
            before = share
            run.angles.append(angle)
        }
        return run
    }

    func testAFiveSecondCloseMovesTheBrightnessByLessThan06PercentPerFrame() {
        let run = close(fadeSeconds: 5)
        XCTAssertLessThan(run.largestStep, 0.006, "A whole degree at once is 0.036")
        XCTAssertEqual(run.turns, 0)
        XCTAssertEqual(run.angles.last, 0)
    }

    func testASlowerCloseMovesItByLess() {
        XCTAssertLessThan(close(fadeSeconds: 10).largestStep, 0.003)
        // Slower than 4 degrees per second: each degree is walked in a
        // quarter of a second.
        XCTAssertLessThan(close(fadeSeconds: 20).largestStep, 0.003)
    }

    func testAFasterCloseMovesItByMoreInProportion() {
        XCTAssertLessThan(close(fadeSeconds: 2).largestStep, 0.015)
        XCTAssertLessThan(close(fadeSeconds: 1).largestStep, 0.03)
        XCTAssertEqual(close(fadeSeconds: 2).turns, 0)
        XCTAssertEqual(close(fadeSeconds: 1).turns, 0)
    }

    func testASensorThatGivesItsValueLessOftenStillHasNoSteps() {
        XCTAssertLessThan(close(fadeSeconds: 5, sensor: 0.02...0.06).largestStep, 0.006)
        XCTAssertLessThan(close(fadeSeconds: 5, sensor: 0.09...0.11).largestStep, 0.006)
        XCTAssertEqual(close(fadeSeconds: 5, sensor: 0.09...0.11).turns, 0)
    }

    func testAt60FramesPerSecondTheStepIsTwiceAsLarge() {
        XCTAssertLessThan(close(fadeSeconds: 5, hz: 60).largestStep, 0.012)
    }

    func testAFastCloseIsNotFarBehind() {
        // 105 degrees per second, as a lid that is shut in half a second.
        var estimator = LidAngleEstimator()
        var time = 0.0
        estimator.update(sample: 60, now: start)
        var behind = 0.0
        while time < 0.5 {
            time += 1.0 / 120
            let truth = 60 - 105 * time
            let angle = estimator.update(sample: truth.rounded(), now: start.addingTimeInterval(time))
            if time > 0.1 { behind = max(behind, angle - truth) }
        }
        XCTAssertLessThan(behind, 3, "Degrees. The closed angle and the lid switch set zero themselves")
    }

    func testALidThatStopsIsNotOvershot() {
        let run = close(fadeSeconds: 5, stopAt: 24.4, extra: 0.5)
        XCTAssertEqual(run.angles.last, 24, "At the value of the sensor")
        XCTAssertGreaterThanOrEqual(run.angles.min() ?? 0, 24, "Never past it")
        XCTAssertEqual(run.turns, 0)
    }

    func testItArrivesWithinAQuarterOfASecond() {
        var estimator = LidAngleEstimator()
        estimator.update(sample: 30, now: start)
        var before = estimator.update(sample: 29, now: start.addingTimeInterval(5))
        XCTAssertEqual(before, 30 - 4.0 / 120, accuracy: 0.0001, "5 seconds late counts as one frame")
        XCTAssertTrue(estimator.isMoving)
        var time = 5.0
        while time < 5.26 {
            time += 1.0 / 120
            let angle = estimator.update(sample: 29, now: start.addingTimeInterval(time))
            XCTAssertLessThanOrEqual(angle, before)
            XCTAssertLessThan(before - angle, 0.04, "4 degrees per second for a step with none before it")
            before = angle
        }
        XCTAssertEqual(estimator.angle, 29)
        XCTAssertFalse(estimator.isMoving)
    }

    func testOneDegreeOfNoiseAtRestChangesNothing() {
        var estimator = LidAngleEstimator()
        var time = 0.0
        for degrees in stride(from: 40.0, through: 30, by: -1) {
            time += 0.1
            estimator.update(sample: degrees, now: start.addingTimeInterval(time))
        }
        for _ in 0..<60 {
            time += 1.0 / 120
            estimator.update(sample: 30, now: start.addingTimeInterval(time))
        }
        XCTAssertEqual(estimator.angle, 30)
        for frame in 0..<600 {
            time += 1.0 / 120
            XCTAssertEqual(estimator.update(sample: frame % 3 == 0 ? 31 : 30, now: start.addingTimeInterval(time)), 30)
        }
        XCTAssertFalse(estimator.isMoving)
    }

    func testNoiseWhileTheLidGoesDownDoesNotTurnTheBrightnessAround() {
        var estimator = LidAngleEstimator()
        var time = 0.0
        var before = 45.0
        estimator.update(sample: 45, now: start)
        for degrees in stride(from: 44.0, through: 10, by: -1) {
            // 44, 45, 44, then 43, 44, 43.
            for sample in [degrees, degrees + 1, degrees, degrees, degrees] {
                time += 1.0 / 120
                let angle = estimator.update(sample: sample, now: start.addingTimeInterval(time))
                XCTAssertLessThanOrEqual(angle, before, "at \(degrees)")
                before = angle
            }
        }
    }

    func testTwoDegreesBackIsAMoveBack() {
        var estimator = LidAngleEstimator()
        estimator.update(sample: 31, now: start)
        var time = 0.0
        for _ in 0..<60 {
            time += 1.0 / 120
            estimator.update(sample: 30, now: start.addingTimeInterval(time))
        }
        time += 1.0 / 120
        XCTAssertEqual(estimator.update(sample: 31, now: start.addingTimeInterval(time)), 30, "One degree back is noise")
        for _ in 0..<60 {
            time += 1.0 / 120
            estimator.update(sample: 32, now: start.addingTimeInterval(time))
        }
        XCTAssertEqual(estimator.angle, 32)
    }

    func testALateUpdateDoesNotJump() {
        var estimator = LidAngleEstimator()
        estimator.update(sample: 60, now: start)
        let angle = estimator.update(sample: 20, now: start.addingTimeInterval(0.5))
        XCTAssertGreaterThan(angle, 58, "The time before the step is not walked")
        var time = 0.5
        var before = angle
        var largest = 0.0
        while time < 1.2 {
            time += 1.0 / 120
            let next = estimator.update(sample: 20, now: start.addingTimeInterval(time))
            largest = max(largest, before - next)
            before = next
        }
        XCTAssertEqual(estimator.angle, 20)
        XCTAssertLessThan(largest, 4, "Degrees per frame, and less with each frame")
    }

    func testTheFirstValueAndAResetAreTakenAsTheyAre() {
        var estimator = LidAngleEstimator()
        XCTAssertNil(estimator.angle)
        XCTAssertEqual(estimator.update(sample: 110, now: start), 110)
        XCTAssertFalse(estimator.isMoving)
        estimator.update(sample: 60, now: start.addingTimeInterval(0.01))
        XCTAssertTrue(estimator.isMoving)
        estimator.reset(to: 3, now: start.addingTimeInterval(0.02))
        XCTAssertEqual(estimator.angle, 3)
        XCTAssertFalse(estimator.isMoving)
    }
}
