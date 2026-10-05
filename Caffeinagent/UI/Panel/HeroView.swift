import SwiftUI

/// The glance: the robot, what the Mac does, and why.
struct HeroView: View {
    let state: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            RobotHero(pose: state.pose)
            VStack(spacing: 2) {
                Text(state.title)
                    .font(.title2)
                Text(state.subtitle)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.subtitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.headlineAccessibilityLabel)
            .accessibilityAddTraits(.isHeader)
        }
    }
}
