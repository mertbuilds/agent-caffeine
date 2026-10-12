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
                if let wakeLine = state.wakeLine {
                    WakeLine(text: wakeLine)
                        .transition(.opacity)
                }
                if let hotspotLine = state.hotspotLine {
                    HotspotLine(text: hotspotLine)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "On your iPhone hotspot since 14:02" on one quiet line below the
/// headline, like the line of the battery.
struct HotspotLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "wifi")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// The wake alarm of "Wake for jobs" on one quiet line below the
/// headline, like the line of the battery.
struct WakeLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "alarm")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
