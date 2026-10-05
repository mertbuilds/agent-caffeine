import XCTest

final class HumaneDurationTests: XCTestCase {
    func testUnits() {
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let cases: [(TimeInterval, String)] = [
            (-5, "a moment"), (0, "a moment"), (59, "a moment"),
            (60, "1 minute"), (119, "1 minute"), (12 * minute, "12 minutes"), (89 * minute + 59, "89 minutes"),
            (90 * minute, "1 hour"), (119 * minute, "1 hour"), (2 * hour, "2 hours"),
            (395 * minute, "6 hours"), (47 * hour + 59 * minute, "47 hours"),
            (48 * hour, "2 days"), (71 * hour, "2 days"), (72 * hour, "3 days"), (30 * 24 * hour, "30 days"),
            (.infinity, "a moment"), (.nan, "a moment"),
        ]
        for (seconds, text) in cases {
            XCTAssertEqual(HumaneDuration.text(seconds: seconds), text, "\(seconds) s")
            XCTAssertFalse(text.contains("min "), text)
        }
        XCTAssertEqual(HumaneDuration.text(minutes: 395), "6 hours")
    }
}
