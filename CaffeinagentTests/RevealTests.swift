import XCTest

final class RevealTests: XCTestCase {
    private func reveal(_ progress: CGFloat, opening: Bool, natural: CGFloat = 148) -> Reveal {
        Reveal(natural: natural, progress: progress, opening: opening)
    }

    func testHeightGoesFromNothingToTheWholePart() {
        XCTAssertEqual(reveal(0, opening: true).height, 0)
        XCTAssertEqual(reveal(0.25, opening: true).height, 37)
        XCTAssertEqual(reveal(0.5, opening: false).height, 74)
        XCTAssertEqual(reveal(1, opening: true).height, 148)
    }

    func testHeightNeverLeavesThePart() {
        // A spring passes its end.
        XCTAssertEqual(reveal(1.08, opening: true).height, 148)
        XCTAssertEqual(reveal(-0.05, opening: false).height, 0)
        XCTAssertEqual(reveal(1, opening: true, natural: -4).height, 0)
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            for opening in [true, false] {
                let height = reveal(progress, opening: opening).height
                XCTAssertGreaterThanOrEqual(height, 0)
                XCTAssertLessThanOrEqual(height, 148)
            }
        }
    }

    func testHeightGrowsWithTheWay() {
        let heights = (0...20).map { reveal(CGFloat($0) / 20, opening: true).height }
        XCTAssertEqual(heights, heights.sorted())
    }

    func testAPartThatOpensFadesInOverTheFirstPartOfTheWay() {
        XCTAssertEqual(reveal(0, opening: true).opacity, 0)
        XCTAssertEqual(reveal(Reveal.fadeIn / 2, opening: true).opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(reveal(Reveal.fadeIn, opening: true).opacity, 1)
        XCTAssertEqual(reveal(1, opening: true).opacity, 1)
    }

    func testAPartThatClosesFadesOutBeforeItIsClosed() {
        XCTAssertEqual(reveal(1, opening: false).opacity, 1)
        XCTAssertEqual(reveal(1 - Reveal.fadeOut / 2, opening: false).opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(reveal(1 - Reveal.fadeOut, opening: false).opacity, 0, accuracy: 0.0001)
        XCTAssertEqual(reveal(0, opening: false).opacity, 0)
    }

    func testOpacityStaysBetweenNothingAndAll() {
        for progress in [-0.2, 0, 0.3, 1, 1.2] as [CGFloat] {
            for opening in [true, false] {
                XCTAssertTrue((0...1).contains(reveal(progress, opening: opening).opacity))
            }
        }
    }

    func testAClosedPartIsOutOfReachFromTheFirstMoment() {
        // Still in view at this moment, but no longer for the pointer or VoiceOver.
        XCTAssertTrue(reveal(1, opening: false).isOutOfReach)
        XCTAssertTrue(reveal(0, opening: false).isOutOfReach)
        XCTAssertFalse(reveal(0, opening: true).isOutOfReach)
        XCTAssertFalse(reveal(1, opening: true).isOutOfReach)
    }

    func testTheFadesAreSharesOfTheWay() {
        XCTAssertTrue(Reveal.fadeIn > 0 && Reveal.fadeIn <= 1)
        XCTAssertTrue(Reveal.fadeOut > 0 && Reveal.fadeOut <= 1)
    }
}
