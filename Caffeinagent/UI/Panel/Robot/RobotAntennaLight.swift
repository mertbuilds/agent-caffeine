import SwiftUI

/// The light of the antenna. The ball of the icon glows on its own. This
/// adds the breath of that glow, and the amber and the red ball. Each
/// part is drawn once into a picture, see `RobotArt`.
enum RobotAntennaLight {
    enum Tint {
        case blue
        case amber
        case red
    }

    /// How strong the halo of a light is that does not breathe.
    static let redStrength = 0.55

    /// The blue halo at a moment of the breath.
    static func blueStrength(pulse: Double) -> Double {
        0.75 * pulse
    }

    static func amberStrength(pulse: Double) -> Double {
        0.5 + 0.5 * pulse
    }

    /// The side of the square a halo fills, in radii of the ball.
    static let haloReach: CGFloat = 5.2
    static let ballReach: CGFloat = 2.04

    static func halo(_ tint: Tint, radius: CGFloat) -> some View {
        let color = color(tint)
        return Circle()
            .fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0.35), color.opacity(0)], center: .center, startRadius: radius * 0.6, endRadius: radius * 2.6))
            .frame(width: radius * haloReach, height: radius * haloReach)
    }

    static func ball(_ tint: Tint, radius: CGFloat) -> some View {
        let colors: [Color]
        switch tint {
        // The blue ball is in the picture of the robot.
        case .blue, .amber: colors = [Color(red: 1.0, green: 0.93, blue: 0.68), color(.amber), Color(red: 0.92, green: 0.56, blue: 0.08)]
        case .red: colors = [Color(red: 1.0, green: 0.66, blue: 0.60), color(.red), Color(red: 0.74, green: 0.10, blue: 0.09)]
        }
        return Circle()
            .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.4, y: 0.34), startRadius: 0, endRadius: radius * 1.25))
            .frame(width: ballReach * radius, height: ballReach * radius)
    }

    /// Without its light the ball is a shade darker.
    static func shade(radius: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0.10, green: 0.20, blue: 0.42).opacity(0.22))
            .frame(width: 2 * radius, height: 2 * radius)
    }

    private static func color(_ tint: Tint) -> Color {
        switch tint {
        case .blue: return Color(red: 0.72, green: 0.90, blue: 1.0)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        case .red: return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
    }
}
