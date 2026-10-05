import SwiftUI

/// The robot of the app icon, drawn in layers so each part can move.
/// `time` drives the loops (bob, steam, glow). Nil holds a still pose.
struct RobotFigure: View {
    let look: RobotLook
    let time: TimeInterval?
    /// 1 while the eyes are shut for a blink.
    var blink: CGFloat = 0
    @Environment(\.robotUnit) private var unit

    private var palette: RobotPalette {
        RobotPalette(saturation: look.saturation, dimming: look.dimming)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.disc)
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: unit * 0.8))
                .padding(.horizontal, unit * 9)
                .padding(.top, unit * 13)
                .padding(.bottom, unit * 5)
            robot
                .scaleEffect(Self.robotScale, anchor: Self.scaleAnchor)
                .offset(y: unit * bobOffset)
            RobotSteam(wisps: look.wisps, time: time)
                .scaleEffect(Self.robotScale, anchor: Self.scaleAnchor)
                .offset(y: unit * (bobOffset - look.cupLift))
            RobotSnooze(time: time)
                .opacity(look.snoozes ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) { badge }
    }

    /// The robot fills its disc a little more than the drawing's numbers give.
    private static let robotScale: CGFloat = 1.1
    private static let scaleAnchor = UnitPoint(x: 0.5, y: 0.6)

    private var bobOffset: CGFloat {
        guard let time else { return 0 }
        return look.bob * CGFloat(sin(time * 2 * .pi / look.bobPeriod))
    }

    private var robot: some View {
        ZStack {
            RobotPart.box(30, 57, 40, 36, radius: 17)
                .fill(palette.body)
            head
                .rotationEffect(.degrees(look.tilt), anchor: UnitPoint(x: 0.5, y: 0.62))
            cup
                .offset(y: -unit * look.cupLift)
        }
    }

    private var head: some View {
        ZStack {
            RobotPart.box(48.3, 11, 3.4, 13, radius: 1.7)
                .fill(palette.shellBottom)
            RobotPart.oval(centerX: 50, centerY: 8.6, radiusX: 5.2, radiusY: 5.2)
                .fill(antennaColor)
                .shadow(color: antennaGlow.opacity(antennaPulse), radius: unit * 3.5)
            RobotPart.box(16.5, 35, 9, 16, radius: 4)
                .fill(palette.shellShade)
            RobotPart.box(74.5, 35, 9, 16, radius: 4)
                .fill(palette.shellShade)
            RobotPart.box(22.5, 21, 55, 43, radius: 20)
                .fill(palette.shell)
            RobotPart.box(29.5, 28, 41, 28, radius: 12.5)
                .fill(palette.visor)
            eyes
        }
    }

    private var eyes: some View {
        ZStack {
            RobotEyeArcs(curve: look.eyeCurve, slant: look.eyeSlant)
                .stroke(palette.eye, style: StrokeStyle(lineWidth: unit * 2.9, lineCap: .round))
                .opacity(1 - look.eyeRound)
            ZStack {
                ForEach(RobotEyeArcs.centers, id: \.self) { x in
                    RobotPart.oval(centerX: x, centerY: RobotEyeArcs.centerY, radiusX: 3.7, radiusY: 3.7)
                        .fill(palette.eye)
                    RobotPart.oval(centerX: x + 1.2, centerY: RobotEyeArcs.centerY - 1.3, radiusX: 1.1, radiusY: 1.1)
                        .fill(.white)
                }
            }
            .scaleEffect(0.5 + 0.5 * look.eyeRound, anchor: UnitPoint(x: 0.5, y: RobotEyeArcs.centerY / 100))
            .opacity(look.eyeRound)
        }
        .scaleEffect(x: 1, y: 1 - 0.9 * blink, anchor: UnitPoint(x: 0.5, y: RobotEyeArcs.centerY / 100))
        .shadow(color: palette.glow.opacity(0.9 * look.eyeBrightness), radius: unit * 2.2)
        .opacity(0.25 + 0.75 * look.eyeBrightness)
    }

    private var cup: some View {
        ZStack {
            RobotPart.oval(centerX: 65, centerY: 77, radiusX: 5, radiusY: 5.4)
                .stroke(palette.cupBottom, lineWidth: unit * 2.8)
            RobotCupBody()
                .fill(palette.cup)
            RobotPart.oval(centerX: 50, centerY: RobotCupBody.rimY, radiusX: 13.5, radiusY: 3.9)
                .fill(palette.cupTop)
            RobotPart.oval(centerX: 50, centerY: RobotCupBody.rimY + 0.5, radiusX: 11.2, radiusY: 2.7)
                .fill(palette.coffee)
            RobotPart.oval(centerX: 31.5, centerY: 81, radiusX: 9.5, radiusY: 8.6)
                .fill(palette.shell)
            RobotPart.oval(centerX: 68.5, centerY: 81, radiusX: 9.5, radiusY: 8.6)
                .fill(palette.shell)
        }
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
                .offset(x: unit * 2, y: -unit * 2)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var antennaColor: Color {
        switch look.antenna {
        case .glowing: return palette.antenna
        case .amber: return palette.amber
        case .dim: return palette.shellShade
        }
    }

    private var antennaGlow: Color {
        switch look.antenna {
        case .glowing: return palette.glow
        case .amber: return palette.amber
        case .dim: return .clear
        }
    }

    /// The glow breathes once in about three seconds.
    private var antennaPulse: Double {
        guard let time else { return 0.8 }
        return 0.7 + 0.3 * sin(time * 2 * .pi / 3.1)
    }
}
