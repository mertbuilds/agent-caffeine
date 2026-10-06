import XCTest

final class HumaneDurationTests: XCTestCase {
    func testUnits() {
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let cases: [(TimeInterval, String?)] = [
            (-5, nil), (0, nil), (59, nil),
            (60, "1 minute"), (119, "1 minute"), (12 * minute, "12 minutes"), (89 * minute + 59, "89 minutes"),
            (90 * minute, "1 hour"), (119 * minute, "1 hour"), (2 * hour, "2 hours"),
            (395 * minute, "6 hours"), (47 * hour + 59 * minute, "47 hours"),
            (48 * hour, "2 days"), (71 * hour, "2 days"), (72 * hour, "3 days"), (30 * 24 * hour, "30 days"),
            (.infinity, nil), (.nan, nil),
        ]
        for (seconds, units) in cases {
            XCTAssertEqual(HumaneDuration.lasting(seconds: seconds), units.map { "for \($0)" }, "\(seconds) s")
            XCTAssertEqual(HumaneDuration.ago(seconds: seconds), "\(units ?? "a moment") ago", "\(seconds) s")
        }
        XCTAssertEqual(HumaneDuration.lasting(minutes: 395), "for 6 hours")
        XCTAssertNil(HumaneDuration.lasting(minutes: 0))
    }

    func testCounted() {
        XCTAssertEqual(HumaneDuration.counted(1, "day"), "1 day")
        XCTAssertEqual(HumaneDuration.counted(2, "day"), "2 days")
    }
}
