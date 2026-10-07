import SwiftUI

/// The robot at the top of the menu. It moves while the menu is open, and
/// a click makes it blink.
struct RobotHero: View {
    let pose: HeroPose
    var size = PanelMetrics.robotSize
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RobotFigure(look: RobotLook(pose: pose), taps: taps)
            .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: pose)
            .environment(\.robotUnit, size / 100)
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: size * RobotGeometry.corner, style: .continuous))
            .onTapGesture(perform: blinkOnce)
            .accessibilityHidden(true)
    }

    private func blinkOnce() {
        if !reduceMotion { taps += 1 }
    }
}
