import SwiftUI

/// The robot of the app icon: its picture, and on top the parts that move.
/// `time` drives the loops (bob, steam, glow, blink). Nil holds a still pose.
struct RobotFigure: View {
    let look: RobotLook
    let time: TimeInterval?
    /// 1 while the eyes are shut for a blink the user asked for.
    var blink: CGFloat = 0
    @Environment(\.robotUnit) private var unit

    private static let bobPeriod: TimeInterval = 3

    var body: some View {
        let side = unit * 100
        let tile = RoundedRectangle(cornerRadius: side * RobotGeometry.corner, style: .continuous)
        // The picture is a little larger than the tile, so the robot can
        // bob behind the tile's edge, which stays where it is.
        picture
            .frame(width: side * RobotGeometry.shownScale, height: side * RobotGeometry.shownScale)
            .offset(y: bobOffset)
            .frame(width: side, height: side)
            .clipShape(tile)
            .overlay(tile.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) { badge }
    }

    private var picture: some View {
        ZStack {
            ZStack {
                Image("RobotBase")
                    .resizable()
                    .interpolation(.high)
                Image("RobotEyes")
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(x: 1, y: 1 - 0.9 * shut, anchor: RobotEyes.anchor)
                    .opacity(iconEyes)
            }
            .saturation(look.saturation)
            .contrast(look.contrast)
            .brightness(-look.dimming)
            RobotEyes(eyes: look.eyes, shut: shut)
            RobotAntennaLight(antenna: look.antenna, time: time)
            RobotSteam(wisps: look.wisps, time: time)
            RobotSnooze(time: time)
                .opacity(look.snoozes ? 1 : 0)
        }
    }

    /// How much of the icon's own eyes shows.
    private var iconEyes: Double {
        switch look.eyes {
        case .happy: return 1
        case .dim: return 0.3
        case .open, .closed, .dead: return 0
        }
    }

    private var shut: CGFloat {
        guard look.blinks, let time else { return blink }
        return max(blink, RobotBlink.closure(at: time))
    }

    private var bobOffset: CGFloat {
        guard let time else { return 0 }
        return look.bob * CGFloat(sin(time * 2 * .pi / Self.bobPeriod))
    }

    @ViewBuilder
    private var badge: some View {
        if let symbol = look.badge {
            Image(systemName: symbol)
                .font(.system(size: unit * 13, weight: .medium))
                .foregroundStyle(symbol.hasPrefix("battery") ? Color.red : Color.orange)
                .frame(width: unit * 28, height: unit * 28)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                .offset(x: unit * 7, y: unit * 5)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}
