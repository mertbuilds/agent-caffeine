import XCTest

final class BrightnessKeyDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_200_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testAJumpWithTheLidAtRestIsTheUsers() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.6, now: at(0))
        XCTAssertNil(keys.read(0.6, rested: true, now: at(0.5)))
        XCTAssertEqual(keys.read(0.6625, rested: true, now: at(1)), 0.6625, "One press: 1/16")
        XCTAssertNil(keys.read(0.6625, rested: true, now: at(1.5)), "Told once")
        XCTAssertEqual(keys.read(0.6, rested: true, now: at(2)), 0.6, "And down again")
    }

    func testWhatTheFadeWroteIsNotTheUsers() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.6, now: at(0))
        keys.wrote(0.3, now: at(0.1))
        XCTAssertNil(keys.read(0.3, rested: true, now: at(0.5)))
        XCTAssertNil(keys.read(0.31, rested: true, now: at(1)))
    }

    func testNothingIsTheUsersWhileTheLidOrTheFadeMoves() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.6, now: at(0))
        XCTAssertNil(keys.read(0.8, rested: false, now: at(0.1)))
        XCTAssertEqual(keys.read(0.8, rested: true, now: at(0.3)), 0.8, "A key from a moment ago is seen at the first quiet reading")
    }

    func testAJumpThatNobodySawComeIsNotTheUsers() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.6, now: at(0))
        // The lid moved for 5 seconds, and macOS moved the brightness.
        XCTAssertNil(keys.read(0.4, rested: true, now: at(5)))
        XCTAssertNil(keys.read(0.4, rested: true, now: at(5.5)))
        XCTAssertEqual(keys.read(0.4625, rested: true, now: at(6)), 0.4625, "A key after it counts from there")
    }

    func testASlowDriftIsFollowedAndIsNotTheUsers() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.6, now: at(0))
        var level: Float = 0.6
        for frame in 1...100 {
            level -= 0.003
            XCTAssertNil(keys.read(level, rested: true, now: at(Double(frame) / 60)), "30 percent in under 2 seconds, a little at a time")
        }
        XCTAssertEqual(keys.steady ?? -1, level, accuracy: 0.0001)
        XCTAssertEqual(keys.read(level + 0.0625, rested: true, now: at(2)), level + 0.0625)
    }

    func testAKeyThatTheSystemAnimatesIsSeenWhenItArrives() {
        var keys = BrightnessKeyDetector()
        keys.wrote(0.5, now: at(0))
        XCTAssertNil(keys.read(0.53, rested: true, now: at(0.50)), "Half way: wait")
        XCTAssertEqual(keys.read(0.5625, rested: true, now: at(0.55)), 0.5625)
    }

    func testTheFirstReadingIsWhereItStarts() {
        var keys = BrightnessKeyDetector()
        XCTAssertNil(keys.read(0.7, rested: true, now: at(0)))
        XCTAssertEqual(keys.steady, 0.7)
    }
}
