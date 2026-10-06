import SwiftUI

/// "9 more idle": opens the rest of the idle agents below it.
struct MoreIdleRow: View {
    let title: String
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: PanelMetrics.logoBox, height: PanelMetrics.logoBox)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: PanelMetrics.logoBoxRadius, style: .continuous))
                    .frame(width: PanelMetrics.logoSlot)
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(.secondary)
            .frame(height: PanelMetrics.idleRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? PanelText.expanded : PanelText.collapsed)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : PanelMetrics.stateChange) { isExpanded.toggle() }
    }
}
