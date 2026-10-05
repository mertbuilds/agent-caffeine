import SwiftUI

/// The steam over the cup: the two wisps of the icon, and a third for a
/// third agent. Each wisp grows out of the coffee, stretches and fades,
/// in a loop of its own phase. Without a time the wisps stand as the icon
/// has them.
struct RobotSteam: View {
    static let period: TimeInterval = 3.6

    let wisps: Int
    let time: TimeInterval?

    /// The large wisp of the icon comes first: one agent, one wisp.
    private static let all: [(rows: [RobotGeometry.WispRow], mirrored: Bool, lag: Double)] = [
        (RobotGeometry.largeWisp, false, 0),
        (RobotGeometry.smallWisp, false, 0.37),
        (RobotGeometry.smallWisp, true, 0.71),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<Self.all.count, id: \.self) { index in
                    let wisp = Self.all[index]
                    // Two of each, half a loop apart, so the steam never
                    // stops: one fades in while the other fades out.
                    ForEach(0..<2, id: \.self) { copy in
                        let phase = phase(lag: wisp.lag, copy: copy)
                        RobotWisp(rows: wisp.rows, mirrored: wisp.mirrored, phase: phase, sway: sway(index))
                            .fill(RobotWisp.fade(wisp.rows, phase: phase))
                            .opacity(pow(sin(.pi * Double(phase)), 2))
                    }
                    .opacity(index < wisps ? 1 : 0)
                }
            }
            .blur(radius: proxy.size.width * 0.002)
        }
    }

    /// 0 where the wisp leaves the coffee, 0.5 where the icon shows it,
    /// 1 where it is gone.
    private func phase(lag: Double, copy: Int) -> CGFloat {
        guard let time else { return copy == 0 ? 0.5 : 0 }
        let shifted = time / Self.period + lag + Double(copy) * 0.5
        return CGFloat(shifted - shifted.rounded(.down))
    }

    private func sway(_ index: Int) -> CGFloat {
        guard let time else { return 0 }
        return CGFloat(sin(time * 2 * .pi / 4.6 + Double(index) * 1.7))
    }
}

/// One wisp, from its outline in the icon.
struct RobotWisp: Shape {
    let rows: [RobotGeometry.WispRow]
    /// The third wisp is the small one, turned round, to the right of the
    /// large one.
    var mirrored = false
    var phase: CGFloat = 0.5
    /// -1 to 1: how far the top leans.
    var sway: CGFloat = 0

    private static let mirrorAxis: CGFloat = 0.545
    private static let lean: CGFloat = 0.007

    /// How tall the wisp is at this phase, as a share of the icon's.
    static func stretch(_ phase: CGFloat) -> CGFloat {
        0.6 + 0.8 * phase
    }

    /// How far it has left the coffee.
    static func lift(_ phase: CGFloat) -> CGFloat {
        0.05 * max(0, phase - 0.5)
    }

    static func height(_ rows: [RobotGeometry.WispRow], y: CGFloat, phase: CGFloat) -> CGFloat {
        let foot = rows[rows.count - 1].y
        return foot - (foot - y) * stretch(phase) - lift(phase)
    }

    /// White, as strong in each row as the icon's steam is there.
    static func fade(_ rows: [RobotGeometry.WispRow], phase: CGFloat) -> LinearGradient {
        let top = height(rows, y: rows[0].y, phase: phase)
        let foot = height(rows, y: rows[rows.count - 1].y, phase: phase)
        let stops = rows.map { row in
            Gradient.Stop(color: .white.opacity(row.strength), location: (height(rows, y: row.y, phase: phase) - top) / (foot - top))
        }
        return LinearGradient(stops: stops, startPoint: UnitPoint(x: 0.5, y: top), endPoint: UnitPoint(x: 0.5, y: foot))
    }

    func path(in rect: CGRect) -> Path {
        let top = rows[0].y
        let foot = rows[rows.count - 1].y
        func point(_ row: RobotGeometry.WispRow, _ x: CGFloat) -> CGPoint {
            // The foot stays in the coffee, the top leans the most.
            let rise = (foot - row.y) / (foot - top)
            let leaned = (mirrored ? 2 * Self.mirrorAxis - x : x) + sway * Self.lean * rise * rise
            return CGPoint(x: leaned * rect.width, y: Self.height(rows, y: row.y, phase: phase) * rect.height)
        }
        var path = Path()
        path.addLines(rows.map { point($0, $0.left) } + rows.reversed().map { point($0, $0.right) })
        path.closeSubpath()
        return path
    }
}
