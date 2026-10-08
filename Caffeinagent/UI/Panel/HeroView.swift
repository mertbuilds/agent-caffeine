import SwiftUI

/// The glance: the robot, and next to it what the Mac does and why.
struct HeroView: View {
    let state: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: PanelMetrics.robotGap) {
            RobotHero(pose: state.pose)
            VStack(alignment: .leading, spacing: PanelMetrics.batteryLineTop) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.title2)
                        .lineLimit(2)
                    // A reason is never cut short.
                    Text(state.subtitle)
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.subtitle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.headlineAccessibilityLabel)
                .accessibilityAddTraits(.isHeader)
                if let battery = state.battery {
                    BatteryLine(battery: battery)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
