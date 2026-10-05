import SwiftUI

/// The robot at the top of the menu. It moves while the menu is open, and
/// a click makes it blink.
struct RobotHero: View {
    let pose: HeroPose
    var size = PanelMetrics.robotSize
    @State private var blink: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MotionClock { time in
            RobotFigure(look: RobotLook(pose: pose), time: time, blink: blink)
                .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: pose)
        }
        .environment(\.robotUnit, size / 100)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture(perform: blinkOnce)
        .accessibilityHidden(true)
    }

    private func blinkOnce() {
        guard !reduceMotion, blink == 0 else { return }
        Task {
            withAnimation(.easeIn(duration: 0.08)) { blink = 1 }
            try? await Task.sleep(nanoseconds: 130_000_000)
            withAnimation(.easeOut(duration: 0.14)) { blink = 0 }
        }
    }
}
