import SwiftUI

/// The eyes the icon does not have: round, shut, and crossed out. They
/// are drawn the way the icon draws its own: a light core with a glow.
struct RobotEyes: View {
    let eyes: RobotLook.Eyes
    /// 1 while the eyes are shut for a blink.
    var shut: CGFloat = 0

    /// The eyes shut towards this height.
    static let anchor = UnitPoint(x: 0.5, y: RobotGeometry.leftEye.top + 0.6 * RobotGeometry.leftEye.sagitta)

    private static let light = Color(red: RobotGeometry.eyeColor.red, green: RobotGeometry.eyeColor.green, blue: RobotGeometry.eyeColor.blue)
    private static let glow = Color(red: 0.24, green: 0.50, blue: 1.0)
    private static let red = Color(red: 1.0, green: 0.36, blue: 0.32)
    private static let redGlow = Color(red: 1.0, green: 0.12, blue: 0.10)

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                RobotOpenEyes()
                    .fill(Self.light)
                    .scaleEffect(x: 1, y: 1 - 0.9 * shut, anchor: Self.anchor)
                    .modifier(Glow(color: Self.glow, side: side))
                    .opacity(eyes == .open ? 1 : 0)
                RobotShutEyes()
                    .stroke(Self.light.opacity(0.85), style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))
                    .modifier(Glow(color: Self.glow.opacity(0.7), side: side))
                    .opacity(eyes == .closed ? 1 : 0)
                RobotDeadEyes()
                    .stroke(Self.red, style: StrokeStyle(lineWidth: side * 0.024, lineCap: .round))
                    .modifier(Glow(color: Self.redGlow, side: side))
                    .opacity(eyes == .dead ? 1 : 0)
            }
        }
    }

    /// The glow of the icon's eyes: strong at the edge, and gone a little
    /// further out.
    private struct Glow: ViewModifier {
        let color: Color
        let side: CGFloat

        func body(content: Content) -> some View {
            content
                .shadow(color: color.opacity(0.9), radius: side * 0.012)
                .shadow(color: color.opacity(0.45), radius: side * 0.035)
        }
    }
}

private extension RobotGeometry.Eye {
    /// The middle of the eye.
    func center(in rect: CGRect) -> CGPoint {
        CGPoint(x: centerX * rect.width, y: (top + sagitta / 2) * rect.height)
    }
}

private let bothEyes = [RobotGeometry.leftEye, RobotGeometry.rightEye]

/// Round eyes that look at the user.
struct RobotOpenEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for eye in bothEyes {
            let center = eye.center(in: rect)
            let radiusX = 0.034 * rect.width
            let radiusY = 0.041 * rect.height
            path.addEllipse(in: CGRect(x: center.x - radiusX, y: center.y - radiusY, width: 2 * radiusX, height: 2 * radiusY))
        }
        return path
    }
}

/// Shut eyes: two lines that sag a little.
struct RobotShutEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for eye in bothEyes {
            let center = eye.center(in: rect)
            let reach = 0.9 * eye.halfChord * rect.width
            let y = center.y + 0.012 * rect.height
            path.move(to: CGPoint(x: center.x - reach, y: y))
            path.addQuadCurve(to: CGPoint(x: center.x + reach, y: y), control: CGPoint(x: center.x, y: y + 0.014 * rect.height))
        }
        return path
    }
}

/// The eyes of a robot that was knocked out: a cross each.
struct RobotDeadEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for eye in bothEyes {
            let center = eye.center(in: rect)
            let reach = 0.031 * rect.width
            for turn in [1.0, -1.0] {
                path.move(to: CGPoint(x: center.x - reach, y: center.y - turn * reach))
                path.addLine(to: CGPoint(x: center.x + reach, y: center.y + turn * reach))
            }
        }
        return path
    }
}
