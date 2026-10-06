import SwiftUI

/// The charge of the battery as a thin bar, with a mark where agent
/// caffeine lets the Mac sleep.
struct BatteryBar: View {
    let battery: PanelBattery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                        .frame(height: PanelMetrics.batteryBarHeight)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(PanelMetrics.batteryBarHeight, width * battery.fill), height: PanelMetrics.batteryBarHeight)
                    if let tick = battery.tick {
                        Rectangle()
                            .fill(.secondary)
                            .frame(width: 1, height: PanelMetrics.batteryTickHeight)
                            .offset(x: (width * tick).rounded())
                    }
                }
                .frame(height: PanelMetrics.batteryTickHeight)
            }
            .frame(height: PanelMetrics.batteryTickHeight)
            HStack(spacing: 8) {
                Text(battery.leading)
                Spacer(minLength: 8)
                Text(battery.trailing)
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.numericText())
        }
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: battery)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.accessibilityLabel)
    }

    private var tint: Color {
        switch battery.level {
        case .normal: return .primary.opacity(0.35)
        case .nearFloor: return PanelMetrics.waitingAmber
        case .stopped, .nearEmpty: return .red
        }
    }
}
