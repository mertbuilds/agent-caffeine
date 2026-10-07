import SwiftUI

/// The letters that drift up from a sleeping robot. Each is drawn once
/// into a picture, see `RobotArt`. `RobotSnoozeMotion` says how they move.
enum RobotSnooze {
    private static let color = Color(red: 0.88, green: 0.95, blue: 1.0)
    private static let glow = Color(red: 0.55, green: 0.80, blue: 1.0)

    /// Round the letter in its picture, so the glow is whole.
    static func margin(side: CGFloat) -> CGFloat {
        (side * 0.05).rounded(.up)
    }

    static func letter(_ index: Int, side: CGFloat) -> some View {
        Text(verbatim: "z")
            .font(.system(size: side * RobotSnoozeMotion.size(letter: index), weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .shadow(color: glow.opacity(0.8), radius: side * 0.015)
            .padding(margin(side: side))
    }
}
