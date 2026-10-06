import SwiftUI

/// One session below the name of its agent: what it is called, then its
/// state. The state goes on a line of its own when both do not fit.
struct AgentChildView: View {
    let child: PanelChild
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if child.detail == nil {
                label
                    .foregroundStyle(.secondary)
                    .frame(height: PanelMetrics.childRowHeight)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PanelMetrics.childGap) {
                        label.fixedSize()
                        Spacer(minLength: 0)
                        detail.fixedSize()
                    }
                    .frame(height: PanelMetrics.childRowHeight)
                    VStack(alignment: .leading, spacing: 0) {
                        label
                        // A long state gets smaller before it is cut.
                        detail.minimumScaleFactor(0.8)
                    }
                    .frame(height: PanelMetrics.childTwoLineHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Under the name of the agent.
        .padding(.leading, PanelMetrics.logoSlot + 8)
        .help(child.hint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(child.accessibilityLabel)
    }

    private var label: some View {
        Text(child.label)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var detail: some View {
        Text(child.detail ?? "")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: child.detail)
    }

    /// For the height of the list before the layout.
    static func height(of child: PanelChild) -> CGFloat {
        guard let detail = child.detail else { return PanelMetrics.childRowHeight }
        let width = TextFit.width(child.label, style: .callout) + PanelMetrics.childGap + TextFit.width(detail, style: .callout, digits: true)
        return width <= PanelMetrics.childWidth ? PanelMetrics.childRowHeight : PanelMetrics.childTwoLineHeight
    }
}
