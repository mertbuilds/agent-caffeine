import SwiftUI

/// A piece of the robot, given on the 100 x 100 canvas of the drawing and
/// scaled to the frame.
struct RobotPart: Shape {
    private var box: CGRect
    /// Nil for an oval.
    private var radius: CGFloat?

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 100
        let scaled = CGRect(x: box.minX * scale, y: box.minY * scale, width: box.width * scale, height: box.height * scale)
        guard let radius else { return Path(ellipseIn: scaled) }
        return Path(roundedRect: scaled, cornerRadius: radius * scale, style: .continuous)
    }

    static func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> RobotPart {
        RobotPart(box: CGRect(x: x, y: y, width: width, height: height), radius: radius)
    }

    static func oval(centerX: CGFloat, centerY: CGFloat, radiusX: CGFloat, radiusY: CGFloat) -> RobotPart {
        RobotPart(box: CGRect(x: centerX - radiusX, y: centerY - radiusY, width: 2 * radiusX, height: 2 * radiusY))
    }
}

/// Both eyes as strokes: an arc that bends with `curve`.
struct RobotEyeArcs: Shape {
    static let centers: [CGFloat] = [41, 59]
    static let centerY: CGFloat = 42

    var curve: CGFloat
    /// Above 0 the inner ends rise, for a worried look.
    var slant: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(curve, slant) }
        set { (curve, slant) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (x, inner) in zip(Self.centers, [1.0, -1.0]) {
            let ends = Self.centerY + 1.9 * curve
            path.move(to: CGPoint(x: x - 4.8, y: ends + inner * slant))
            path.addQuadCurve(to: CGPoint(x: x + 4.8, y: ends - inner * slant), control: CGPoint(x: x, y: Self.centerY - 6.4 * curve))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
    }
}

/// The cup from the side, with its rim at `rimY`.
struct RobotCupBody: Shape {
    static let rimY: CGFloat = 68.5

    func path(in rect: CGRect) -> Path {
        let y = Self.rimY
        var path = Path()
        path.move(to: CGPoint(x: 36.5, y: y))
        path.addCurve(to: CGPoint(x: 50, y: y + 21), control1: CGPoint(x: 36.5, y: y + 13), control2: CGPoint(x: 41, y: y + 21))
        path.addCurve(to: CGPoint(x: 63.5, y: y), control1: CGPoint(x: 59, y: y + 21), control2: CGPoint(x: 63.5, y: y + 13))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
    }
}

/// One wisp of steam: an S that rises from `origin` and leans with `sway`.
struct RobotSteamWisp: Shape {
    var originX: CGFloat
    var originY: CGFloat
    var sway: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: originX, y: originY))
        path.addCurve(
            to: CGPoint(x: originX + 0.4 * sway, y: originY - 7),
            control1: CGPoint(x: originX - 3.2 - sway, y: originY - 2.4),
            control2: CGPoint(x: originX + 3.2 + sway, y: originY - 4.6)
        )
        path.addCurve(
            to: CGPoint(x: originX - 0.4 * sway, y: originY - 14),
            control1: CGPoint(x: originX - 2.6 - sway, y: originY - 9.4),
            control2: CGPoint(x: originX + 2.6, y: originY - 11.6)
        )
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
    }
}
