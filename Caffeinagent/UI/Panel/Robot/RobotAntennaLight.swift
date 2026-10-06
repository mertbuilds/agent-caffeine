import SwiftUI

/// The light of the antenna. The ball of the icon glows on its own. This
/// adds the breath of that glow, and the amber and the red ball.
struct RobotAntennaLight: View {
    static let pulsePeriod: TimeInterval = 3.1

    let antenna: RobotLook.Antenna
    let time: TimeInterval?

    private static let blue = Color(red: 0.72, green: 0.90, blue: 1.0)
    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.20)
    private static let red = Color(red: 1.0, green: 0.27, blue: 0.23)

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let center = CGPoint(x: RobotGeometry.antennaCenter.x * side, y: RobotGeometry.antennaCenter.y * side)
            let radius = RobotGeometry.antennaRadius * side
            ZStack {
                halo(Self.blue, strength: 0.75 * pulse, radius: radius)
                    .opacity(antenna == .glowing ? 1 : 0)
                halo(Self.blue, strength: 0.75 * Self.rest, radius: radius)
                    .opacity(antenna == .steady ? 1 : 0)
                Group {
                    halo(Self.amber, strength: 0.5 + 0.5 * pulse, radius: radius)
                    ball([Color(red: 1.0, green: 0.93, blue: 0.68), Self.amber, Color(red: 0.92, green: 0.56, blue: 0.08)], radius: radius)
                }
                .opacity(antenna == .amber ? 1 : 0)
                Group {
                    halo(Self.red, strength: 0.55, radius: radius)
                    ball([Color(red: 1.0, green: 0.66, blue: 0.60), Self.red, Color(red: 0.74, green: 0.10, blue: 0.09)], radius: radius)
                }
                .opacity(antenna == .red ? 1 : 0)
                // Without its light the ball is a shade darker.
                Circle()
                    .fill(Color(red: 0.10, green: 0.20, blue: 0.42).opacity(0.22))
                    .frame(width: 2 * radius, height: 2 * radius)
                    .opacity(antenna == .dark ? 1 : 0)
            }
            .position(center)
        }
    }

    private func halo(_ color: Color, strength: Double, radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.9), color.opacity(0.35), color.opacity(0)], center: .center, startRadius: radius * 0.6, endRadius: radius * 2.6))
            .frame(width: radius * 5.2, height: radius * 5.2)
            .opacity(strength)
    }

    private func ball(_ colors: [Color], radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.4, y: 0.34), startRadius: 0, endRadius: radius * 1.25))
            .frame(width: 2.04 * radius, height: 2.04 * radius)
    }

    /// The middle of the breath, where a light that does not breathe stays.
    private static let rest = 0.65

    /// Between 0.3 and 1, once in about three seconds.
    private var pulse: Double {
        guard let time else { return Self.rest }
        return Self.rest + 0.35 * sin(time * 2 * .pi / Self.pulsePeriod)
    }
}
