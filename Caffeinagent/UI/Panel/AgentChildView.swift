import SwiftUI

/// One session below the name of its agent: what it is called, then its
/// state. The group decides whether the state goes on a line of its own.
struct AgentChildView: View {
    let child: PanelChild
    let layout: ChildLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if child.detail == nil {
                label
                    .foregroundStyle(.secondary)
                    .frame(height: PanelMetrics.childRowHeight)
            } else {
                // One stack for both shapes, so the texts move when the shape changes.
                stack {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    // A long state gets smaller before it is cut.
                    detail
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: layout == .oneLine, vertical: false)
                }
                .frame(height: Self.height(of: child, layout: layout))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Under the name of the agent.
        .padding(.leading, PanelMetrics.logoSlot + 8)
        .help(child.hint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(child.accessibilityLabel)
    }

    private var stack: AnyLayout {
        switch layout {
        case .oneLine: AnyLayout(HStackLayout(spacing: PanelMetrics.childGap))
        case .twoLines: AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        }
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

    /// Nil for a count, which is one line in both shapes.
    static func widths(of child: PanelChild) -> ChildLayout.Widths? {
        guard let detail = child.detail else { return nil }
        return ChildLayout.Widths(
            label: TextFit.width(child.label, style: .callout),
            detail: TextFit.width(ChildLayout.reserved(detail), style: .callout, digits: true)
        )
    }

    /// For the height of the list before the layout.
    static func height(of child: PanelChild, layout: ChildLayout) -> CGFloat {
        child.detail == nil || layout == .oneLine ? PanelMetrics.childRowHeight : PanelMetrics.childTwoLineHeight
    }
}
