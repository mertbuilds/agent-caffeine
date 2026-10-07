import SwiftUI

/// One wisp of the steam over the cup, from its outline in the icon, as
/// the icon shows it. It is drawn once into a picture, see `RobotArt`.
/// `RobotSteamMotion` says how the picture moves.
struct RobotWisp: Shape {
    let rows: [RobotGeometry.WispRow]
    /// The third wisp is the small one, turned round, to the right of the
    /// large one.
    var mirrored = false

    private static let mirrorAxis: CGFloat = 0.545

    /// The two wisps of the icon come first.
    static let all: [RobotWisp] = [
        RobotWisp(rows: RobotGeometry.largeWisp),
        RobotWisp(rows: RobotGeometry.smallWisp),
        RobotWisp(rows: RobotGeometry.smallWisp, mirrored: true),
    ]

    /// White, as strong in each row as the icon's steam is there.
    var fade: LinearGradient {
        let top = rows[0].y
        let foot = rows[rows.count - 1].y
        let stops = rows.map { Gradient.Stop(color: .white.opacity($0.strength), location: ($0.y - top) / (foot - top)) }
        return LinearGradient(stops: stops, startPoint: UnitPoint(x: 0.5, y: top), endPoint: UnitPoint(x: 0.5, y: foot))
    }

    /// The wisp as the menu draws it.
    func drawn(side: CGFloat) -> some View {
        fill(fade).blur(radius: side * 0.002)
    }

    /// Where the wisp stands in the coffee, as a share of the picture. It
    /// stretches and leans from here.
    var foot: CGPoint {
        let row = rows[rows.count - 1]
        return CGPoint(x: x((row.left + row.right) / 2), y: row.y)
    }

    /// From the foot to the top, as a share of the picture.
    var height: CGFloat {
        rows[rows.count - 1].y - rows[0].y
    }

    private func x(_ x: CGFloat) -> CGFloat {
        mirrored ? 2 * Self.mirrorAxis - x : x
    }

    func path(in rect: CGRect) -> Path {
        func point(_ row: RobotGeometry.WispRow, _ x: CGFloat) -> CGPoint {
            CGPoint(x: self.x(x) * rect.width, y: row.y * rect.height)
        }
        var path = Path()
        path.addLines(rows.map { point($0, $0.left) } + rows.reversed().map { point($0, $0.right) })
        path.closeSubpath()
        return path
    }
}
