import SwiftUI

/// The robot of the app icon: its tile, the robot over it, and on top the
/// parts that move. The tile stays still. The robot floats over it while
/// the menu is open.
struct RobotFigure: View {
    let look: RobotLook
    /// 1 while the eyes are shut for a blink the user asked for.
    var blink: CGFloat = 0
    /// True while the robot is on its way up or at the top of its float.
    @State private var lifted = false
    @Environment(\.robotUnit) private var unit
    @Environment(\.panelIsOpen) private var isOpen
    @Environment(\.panelFrozenTime) private var frozenTime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = unit * 100
        let tile = RoundedRectangle(cornerRadius: side * RobotGeometry.corner, style: .continuous)
        ZStack {
            ZStack {
                Image("RobotTile")
                    .resizable()
                    .interpolation(.high)
                ZStack {
                    Image("RobotBody")
                        .resizable()
                        .interpolation(.high)
                    MotionClock(runs: look.blinks && iconEyes > 0) { time in
                        Image("RobotEyes")
                            .resizable()
                            .interpolation(.high)
                            .opacity(iconEyes * Double(1 - shut(at: time)))
                    }
                }
                .modifier(lift)
            }
            .saturation(look.saturation)
            .contrast(look.contrast)
            .brightness(-look.dimming)
            MotionClock(runs: look.blinks || look.wisps > 0 || look.antenna == .glowing || look.antenna == .amber) { time in
                ZStack {
                    RobotEyes(eyes: look.eyes, shut: shut(at: time))
                    RobotAntennaLight(antenna: look.antenna, time: time)
                    RobotSteam(wisps: look.wisps, time: time)
                }
            }
            .modifier(lift)
            MotionClock(runs: look.snoozes) { time in
                RobotSnooze(time: time)
            }
            .opacity(look.snoozes ? 1 : 0)
        }
        // The pictures are a little larger than the tile's rounded square.
        .frame(width: side * RobotGeometry.shownScale, height: side * RobotGeometry.shownScale)
        .frame(width: side, height: side)
        .clipShape(tile)
        .overlay(tile.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) { badge }
        .onAppear { float(floats) }
        .onChange(of: floats) { float($0) }
    }

    private var floats: Bool {
        RobotFloat.runs(travel: look.bob, isOpen: isOpen, reduceMotion: reduceMotion, frozen: frozenTime != nil)
    }

    private var lift: RobotLift {
        let rise = frozenTime.map(RobotFloat.rise(at:)) ?? (lifted ? 1 : 0)
        return RobotLift(rise: look.bob > 0 ? rise : 0, travel: look.bob * unit)
    }

    /// The loop is attached only while the robot floats. A change that
    /// does not repeat takes its place when the menu closes, so a closed
    /// menu animates nothing.
    private func float(_ on: Bool) {
        withAnimation(on ? RobotFloat.loop : RobotFloat.settle) { lifted = on }
    }

    /// How much of the icon's own eyes shows.
    private var iconEyes: Double {
        switch look.eyes {
        case .happy: return 1
        case .dim: return 0.3
        case .open, .closed, .dead: return 0
        }
    }

    private func shut(at time: TimeInterval?) -> CGFloat {
        guard look.blinks, let time else { return blink }
        return max(blink, RobotBlink.closure(at: time))
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

/// Lifts the robot off its tile and lets it grow a touch on the way up.
private struct RobotLift: ViewModifier {
    /// 0 on the tile, 1 at the top.
    let rise: CGFloat
    /// In points of the menu.
    let travel: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + RobotFloat.growth * rise)
            .offset(y: -travel * rise)
    }
}

extension RobotFloat {
    static var loop: Animation {
        .timingCurve(ease.x1, ease.y1, ease.x2, ease.y2, duration: period / 2).repeatForever(autoreverses: true)
    }

    static let settle = Animation.easeOut(duration: 0.3)
}
