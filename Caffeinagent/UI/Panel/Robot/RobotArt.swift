import SwiftUI

/// The parts of the robot that move, each drawn once into a picture. Core
/// Animation moves, scales and fades the pictures, so nothing is drawn
/// again for a frame.
@MainActor
enum RobotArt {
    enum Part: Hashable {
        case openEyes
        case shutEyes
        case deadEyes
        case halo(RobotAntennaLight.Tint)
        case ball(RobotAntennaLight.Tint)
        case shade
        case wisp(Int)
        case snooze(Int)
    }

    struct Piece {
        let image: CGImage
        /// Where the picture lies in the picture of the robot, in points.
        /// A letter lies at its own corner.
        let frame: CGRect
    }

    private struct Key: Hashable {
        let part: Part
        let side: CGFloat
        let scale: CGFloat
    }

    private static var pieces: [Key: Piece] = [:]
    /// A wisp and a letter are drawn this much finer than the screen, so
    /// they stay sharp when they stretch and between two pixels.
    private static let fine: CGFloat = 2

    /// - Parameters:
    ///   - side: of the picture of the robot, in points.
    ///   - scale: pixels per point of the screen.
    static func piece(_ part: Part, side: CGFloat, scale: CGFloat) -> Piece? {
        let key = Key(part: part, side: side, scale: scale)
        if let piece = pieces[key] { return piece }
        let piece = draw(part, side: side, scale: scale)
        pieces[key] = piece
        return piece
    }

    private static func draw(_ part: Part, side: CGFloat, scale: CGFloat) -> Piece? {
        let whole = CGRect(x: 0, y: 0, width: side, height: side)
        let radius = RobotGeometry.antennaRadius * side
        switch part {
        case .openEyes: return cut(RobotEyes.open(side: side), whole, side: side, scale: scale)
        case .shutEyes: return cut(RobotEyes.shut(side: side), whole, side: side, scale: scale)
        case .deadEyes: return cut(RobotEyes.dead(side: side), whole, side: side, scale: scale)
        case .halo(let tint):
            return cut(atAntenna(RobotAntennaLight.halo(tint, radius: radius), side: side), antenna(reach: RobotAntennaLight.haloReach, side: side), side: side, scale: scale)
        case .ball(let tint):
            return cut(atAntenna(RobotAntennaLight.ball(tint, radius: radius), side: side), antenna(reach: RobotAntennaLight.ballReach, side: side), side: side, scale: scale)
        case .shade:
            return cut(atAntenna(RobotAntennaLight.shade(radius: radius), side: side), antenna(reach: 2, side: side), side: side, scale: scale)
        case .wisp(let index):
            let wisp = RobotWisp.all[index]
            let frame = wisp.path(in: whole).boundingRect.insetBy(dx: -2, dy: -2).integral
            return cut(wisp.drawn(side: side), frame, side: side, scale: fine * scale)
        case .snooze(let index):
            let renderer = ImageRenderer(content: RobotSnooze.letter(index, side: side))
            renderer.scale = fine * scale
            guard let image = renderer.cgImage else { return nil }
            let margin = RobotSnooze.margin(side: side)
            let size = CGSize(width: CGFloat(image.width) / renderer.scale, height: CGFloat(image.height) / renderer.scale)
            return Piece(image: image, frame: CGRect(origin: CGPoint(x: -margin, y: -margin), size: size))
        }
    }

    private static func atAntenna<V: View>(_ view: V, side: CGFloat) -> some View {
        view.position(x: RobotGeometry.antennaCenter.x * side, y: RobotGeometry.antennaCenter.y * side)
    }

    /// The square round the antenna's ball, on whole points.
    private static func antenna(reach: CGFloat, side: CGFloat) -> CGRect {
        let half = reach * RobotGeometry.antennaRadius * side / 2
        return CGRect(x: RobotGeometry.antennaCenter.x * side - half, y: RobotGeometry.antennaCenter.y * side - half, width: 2 * half, height: 2 * half)
            .insetBy(dx: -1, dy: -1).integral
    }

    /// Draws a view that fills the picture of the robot, and keeps `frame` of it.
    private static func cut<V: View>(_ view: V, _ frame: CGRect, side: CGFloat, scale: CGFloat) -> Piece? {
        let content = view
            .frame(width: side, height: side)
            .offset(x: -frame.minX, y: -frame.minY)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.cgImage.map { Piece(image: $0, frame: frame) }
    }
}
