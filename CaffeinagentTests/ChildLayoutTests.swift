import XCTest

final class ChildLayoutTests: XCTestCase {
    private func widths(_ pairs: [(CGFloat, CGFloat)]) -> [ChildLayout.Widths] {
        pairs.map { ChildLayout.Widths(label: $0.0, detail: $0.1) }
    }

    func testSessionsThatAllFitStandOnOneLine() {
        XCTAssertEqual(ChildLayout.decide(widths([(50, 140), (40, 140)]), gap: 12, available: 240), .oneLine)
    }

    func testOneSessionThatDoesNotFitPutsAllOnTwoLines() {
        XCTAssertEqual(ChildLayout.decide(widths([(50, 140), (150, 140), (40, 140)]), gap: 12, available: 240), .twoLines)
    }

    func testTheGapCountsAndTheExactWidthFits() {
        XCTAssertEqual(ChildLayout.decide(widths([(88, 140)]), gap: 12, available: 240), .oneLine)
        XCTAssertEqual(ChildLayout.decide(widths([(89, 140)]), gap: 12, available: 240), .twoLines)
    }

    func testAGroupWithNoMeasuredSessionStandsOnOneLine() {
        XCTAssertEqual(ChildLayout.decide([], gap: 12, available: 240), .oneLine)
    }

    func testTheShapeFollowsTheSessionsThatComeAndGo() {
        let short = widths([(50, 140), (40, 140)])
        let long = ChildLayout.Widths(label: 150, detail: 140)
        XCTAssertEqual(ChildLayout.decide(short + [long], gap: 12, available: 240), .twoLines)
        XCTAssertEqual(ChildLayout.decide(short, gap: 12, available: 240), .oneLine)
    }

    func testANumberOfOneDigitIsMeasuredAsTwo() {
        XCTAssertEqual(ChildLayout.reserved("Working for 6 minutes"), "Working for 66 minutes")
        XCTAssertEqual(ChildLayout.reserved("Working for 14 minutes"), "Working for 14 minutes")
        XCTAssertEqual(ChildLayout.reserved("Running 3 commands for 9 minutes"), "Running 33 commands for 99 minutes")
        XCTAssertEqual(ChildLayout.reserved("Idle for 5"), "Idle for 55")
        XCTAssertEqual(ChildLayout.reserved("Waiting for your answer"), "Waiting for your answer")
    }

    func testADurationThatGetsASecondDigitKeepsTheShape() {
        // Seven points a character, and a width where "9 minutes" fits and "10 minutes" does not.
        func shape(_ detail: String, reserve: Bool) -> ChildLayout {
            let text = reserve ? ChildLayout.reserved(detail) : detail
            return ChildLayout.decide([ChildLayout.Widths(label: 80, detail: CGFloat(text.count) * 7)], gap: 12, available: 240)
        }
        XCTAssertEqual(shape("Working for 9 minutes", reserve: false), .oneLine)
        XCTAssertEqual(shape("Working for 10 minutes", reserve: false), .twoLines)
        let shapes = (1...59).map { shape("Working for \($0) minutes".replacingOccurrences(of: "for 1 minutes", with: "for 1 minute"), reserve: true) }
        XCTAssertEqual(Set(shapes), [.twoLines])
    }

    func testHoursAndMinutesAreMeasuredInTheirLongestForm() {
        XCTAssertEqual(ChildLayout.reserved("Working for 1 hour"), "Working for 1 hours 59 minutes")
        XCTAssertEqual(ChildLayout.reserved("Working for 1 hour 1 minute"), "Working for 1 hours 59 minutes")
        XCTAssertEqual(ChildLayout.reserved("Idle for 3 hours 5 minutes"), "Idle for 3 hours 59 minutes")
        XCTAssertEqual(ChildLayout.reserved("Running 3 commands for 2 hours"), "Running 33 commands for 2 hours 59 minutes")
        XCTAssertEqual(ChildLayout.reserved("Working for 1 minute"), "Working for 11 minutes")
        XCTAssertEqual(ChildLayout.reserved("Idle for 13 hours"), "Idle for 13 hours")
        XCTAssertEqual(ChildLayout.reserved("Idle for 1 day"), "Idle for 11 days")
        XCTAssertEqual(ChildLayout.reserved("Idle for 3 days"), "Idle for 33 days")
    }

    /// Every minute from one hour to ten: the measured text has one length,
    /// so the group keeps its shape while the duration counts.
    func testADurationInHoursAndMinutesKeepsTheShape() {
        let lengths = (60..<600).map { ChildLayout.reserved("Working \(HumaneDuration.lasting(minutes: $0) ?? "")").count }
        XCTAssertEqual(Set(lengths).count, 1)
        let minutes = (1..<60).map { ChildLayout.reserved("Working \(HumaneDuration.lasting(minutes: $0) ?? "")").count }
        XCTAssertEqual(Set(minutes).count, 1)
    }
}
