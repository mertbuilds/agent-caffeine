import AppKit
import XCTest

final class MenuBarIconTests: XCTestCase {
    /// The eyes of the robot in the menu, as the menu bar draws them.
    private func eyes(_ eyes: RobotLook.Eyes) -> MenuBarLook.Eyes {
        switch eyes {
        case .happy: return .happy
        case .open: return .open
        case .closed, .dim: return .closed
        case .dead: return .dead
        }
    }

    func testTheMenuBarShowsThePoseOfTheHeroInEveryFixture() {
        XCTAssertGreaterThanOrEqual(PanelFixtures.all.count, 12)
        for (name, state) in PanelFixtures.all {
            let hero = RobotLook(pose: state.pose)
            let bar = MenuBarLook(pose: state.pose)
            var drawn = MenuBarLook(look: hero)
            drawn.paused = state.pose == .paused
            XCTAssertEqual(bar, drawn, name)
            XCTAssertEqual(bar.eyes, eyes(hero.eyes), name)
            // A solid head exactly while the title says the Mac stays awake.
            XCTAssertEqual(bar.solid, state.title == PanelText.awakeTitle, name)
            XCTAssertEqual(bar.opacity < 1, hero.eyes == .dim, name)
        }
        let poses = Set(PanelFixtures.all.map { MenuBarLook(pose: $0.state.pose) })
        XCTAssertEqual(poses.count, 6, "Awake, waiting, can sleep, paused, off and knocked out are all among the fixtures")
    }

    func testEveryPose() {
        let cases: [(HeroPose, MenuBarLook, String)] = [
            (.awake(wisps: 2), MenuBarLook(eyes: .happy, solid: true), "agent caffeine: your Mac stays awake"),
            (.awake(wisps: 3), MenuBarLook(eyes: .happy, solid: true), "agent caffeine: your Mac stays awake"),
            (.attentive, MenuBarLook(eyes: .open, solid: true), "agent caffeine: an agent is waiting for you"),
            (.asleep, MenuBarLook(eyes: .closed, solid: false), "agent caffeine: your Mac can sleep"),
            (.off, MenuBarLook(eyes: .closed, solid: false, opacity: 0.45), "agent caffeine: off"),
            (.paused, MenuBarLook(eyes: .closed, solid: false, paused: true), "agent caffeine: paused"),
            (.safetyStop(.battery), MenuBarLook(eyes: .dead, solid: false), "agent caffeine: needs attention"),
            (.safetyStop(.heat), MenuBarLook(eyes: .dead, solid: false), "agent caffeine: needs attention"),
            (.helperOff, MenuBarLook(eyes: .dead, solid: false), "agent caffeine: needs attention"),
        ]
        for (pose, look, label) in cases {
            XCTAssertEqual(MenuBarLook(pose: pose), look, "\(pose)")
            XCTAssertEqual(look.accessibilityLabel, label)
        }
    }

    func testOnlyTheKnockedOutRobotLeavesTheTemplate() {
        for pose in [HeroPose.awake(wisps: 2), .attentive, .asleep, .paused, .off, .helperOff] {
            let look = MenuBarLook(pose: pose)
            let image = MenuBarIcon.image(for: look)
            XCTAssertEqual(image.size, MenuBarIcon.size)
            XCTAssertEqual(image.isTemplate, !(MenuBarIcon.redCrosses && look.eyes == .dead), "\(pose)")
            XCTAssertEqual(image.accessibilityDescription, look.accessibilityLabel)
            XCTAssertTrue(MenuBarIcon.image(for: look) === image, "One picture for each look")
        }
        XCTAssertTrue(MenuBarIcon.make(MenuBarLook(pose: .helperOff), colored: false).isTemplate)
    }

    /// The drawing at 1x and 2x: some ink, and none outside the canvas.
    func testEveryLookDraws() throws {
        for pose in [HeroPose.awake(wisps: 2), .attentive, .asleep, .off, .helperOff] {
            for scale in [1, 2] {
                let (width, height) = (Int(MenuBarIcon.size.width) * scale, Int(MenuBarIcon.size.height) * scale)
                let context = try XCTUnwrap(CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
                let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                MenuBarIcon.draw(MenuBarLook(pose: pose), in: context, ink: black, crosses: black)
                let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
                let inked = (0..<width * height).filter { pixels[$0 * 4 + 3] > 0 }.count
                XCTAssertGreaterThan(inked, width * height / 8, "\(pose) at \(scale)x")
                XCTAssertLessThan(inked, width * height * 3 / 4, "\(pose) at \(scale)x")
            }
        }
    }
}
