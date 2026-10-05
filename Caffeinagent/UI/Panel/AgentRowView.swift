import SwiftUI

/// One agent. A working or waiting agent has its state below the name, an
/// idle one at the trailing edge.
struct AgentRowView: View {
    let row: PanelRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            AgentLogoView(agentID: row.agentID)
                .opacity(row.state == .idle ? 0.55 : 1)
                .frame(width: PanelMetrics.logoSlot, height: PanelMetrics.logoSlot)
                .overlay { StateRing(state: row.state) }
            if row.state == .idle {
                title
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                detail
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    detail
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: row.state == .idle ? PanelMetrics.idleRowHeight : PanelMetrics.activeRowHeight)
        .help(row.hint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var title: some View {
        Text(row.title)
            .font(.body)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var detail: some View {
        Text(row.detail)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: row.detail)
            .layoutPriority(1)
    }
}
