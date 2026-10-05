import XCTest

final class AgentLogoTests: XCTestCase {
    func testPathCommands() {
        XCTAssertEqual(SVGPath.cgPath("M2 3h10v5H2z").boundingBoxOfPath, CGRect(x: 2, y: 3, width: 10, height: 5))
        XCTAssertEqual(SVGPath.cgPath("m2 3 10 0 0 5-10 0z").boundingBoxOfPath, CGRect(x: 2, y: 3, width: 10, height: 5), "Pairs after a move are lines")
        XCTAssertEqual(SVGPath.cgPath("M0 0L4 0V4H0ZM10,10l1,1").boundingBoxOfPath, CGRect(x: 0, y: 0, width: 11, height: 11))
        XCTAssertEqual(SVGPath.cgPath("M.5.5l1e1-.5").boundingBoxOfPath, CGRect(x: 0.5, y: 0, width: 10, height: 0.5))
        let curve = SVGPath.cgPath("M0 0C0 10 10 10 10 0S20-10 20 0").boundingBoxOfPath
        XCTAssertEqual(curve.maxX, 20, accuracy: 0.001)
        XCTAssertEqual(curve.minY, -7.5, accuracy: 0.001)
        XCTAssertEqual(curve.maxY, 7.5, accuracy: 0.001)
    }

    func testArcs() {
        // Two half circles, the flags written without a separator.
        let circle = SVGPath.cgPath("M12 2a10 10 0 100 20 10 10 0 000-20z").boundingBoxOfPath
        for (got, want) in [(circle.minX, 2.0), (circle.minY, 2), (circle.maxX, 22), (circle.maxY, 22)] {
            XCTAssertEqual(got, want, accuracy: 0.001)
        }
        // A quarter turn, clockwise on a canvas with y down.
        let quarter = SVGPath.cgPath("M0 4A4 4 0 014 0")
        XCTAssertTrue(quarter.contains(CGPoint(x: 1.5, y: 1.5)), "The arc bulges to the corner")
        XCTAssertFalse(SVGPath.cgPath("M0 4A4 4 0 004 0L4 4z").contains(CGPoint(x: 0.9, y: 0.9)), "The other sweep bulges away from it")
    }

    func testEveryMarkDrawsOnItsCanvas() {
        XCTAssertEqual(AgentLogo.marks.count, 26)
        // Some marks of the site reach a hair past the canvas.
        let canvas = CGRect(x: 0, y: 0, width: AgentLogo.canvas, height: AgentLogo.canvas).insetBy(dx: -0.25, dy: -0.25)
        for (name, logo) in AgentLogo.marks {
            XCTAssertFalse(logo.layers.isEmpty, name)
            let boxes = logo.layers.map { SVGPath.cgPath($0.path).boundingBoxOfPath }
            for box in boxes {
                XCTAssertFalse(box.isNull || box.isEmpty, "\(name) \(box)")
                XCTAssertTrue(canvas.contains(box), "\(name) \(box)")
            }
            let whole = boxes.reduce(CGRect.null) { $0.union($1) }
            XCTAssertTrue(whole.width > 12 && whole.height > 12, "\(name) \(whole)")
        }
    }

    func testEveryMarkBelongsToAnAgentOfTheCatalog() {
        let known = Set(AgentCatalog.standard.definitions.map(\.id))
        for (id, mark) in AgentLogo.markByAgentID {
            XCTAssertTrue(known.contains(id), id)
            XCTAssertNotNil(AgentLogo.marks[mark], mark)
        }
        XCTAssertEqual(Set(AgentLogo.markByAgentID.values), Set(AgentLogo.marks.keys), "No mark is left without an agent")
        XCTAssertNotNil(AgentLogo.mark(forAgentID: "claude"))
        XCTAssertNil(AgentLogo.mark(forAgentID: "aider"))
        XCTAssertNil(AgentLogo.mark(forAgentID: "user:mytool"))
    }
}
