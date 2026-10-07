import SwiftUI

/// The header line of a group. One session that works or waits has its
/// state below the name. An idle agent has it at the trailing edge, and
/// so has an agent with several sessions when the summary fits there.
struct AgentRowView: View {
    enum SummaryPlace {
        case below
        case trailing
        /// At the trailing edge when it fits next to the name.
        case whereItFits
    }

    let row: PanelRow
    let summary: SummaryPlace
    /// Nil for a line that does not open.
    var isOpen: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch summary {
            case .below:
                line(summaryIsTrailing: false, whole: false)
            case .trailing:
                line(summaryIsTrailing: true, whole: false)
            case .whereItFits:
                ViewThatFits(in: .horizontal) {
                    line(summaryIsTrailing: true, whole: true)
                    line(summaryIsTrailing: false, whole: false)
                }
            }
        }
        .help(PanelText.help(goTo: row.goTo, hint: row.hint))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// - Parameter whole: the name is never cut, so the line says how
    ///   wide it has to be.
    private func line(summaryIsTrailing: Bool, whole: Bool) -> some View {
        HStack(spacing: 8) {
            AgentLogoView(agentID: row.agentID)
                .opacity(row.state == .idle ? 0.55 : 1)
                .frame(width: PanelMetrics.logoSlot, height: PanelMetrics.logoSlot)
                .overlay { StateRing(state: row.state) }
            if summaryIsTrailing {
                title
                    .foregroundStyle(row.state == .idle ? .secondary : .primary)
                    .fixedSize(horizontal: whole, vertical: false)
                Spacer(minLength: 8)
                detail
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    detail
                }
                Spacer(minLength: 0)
            }
            if let isOpen {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: PanelMetrics.chevronWidth)
            }
        }
        .frame(height: summaryIsTrailing ? PanelMetrics.idleRowHeight : PanelMetrics.activeRowHeight)
    }

    private var title: some View {
        Text(row.title)
            .font(.body)
            .lineLimit(1)
            // A session name is cut at its end, so the folder stays.
            .truncationMode(row.distinction == nil ? .middle : .tail)
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

    /// For the height of the list before the layout.
    static func height(of row: PanelRow, summary: SummaryPlace) -> CGFloat {
        switch summary {
        case .below: return PanelMetrics.activeRowHeight
        case .trailing: return PanelMetrics.idleRowHeight
        case .whereItFits:
            let name = TextFit.width(row.title, style: .body)
            let text = TextFit.width(row.detail, style: .callout, digits: true)
            return name + 8 + text + 8 + PanelMetrics.chevronWidth <= PanelMetrics.childWidth ? PanelMetrics.idleRowHeight : PanelMetrics.activeRowHeight
        }
    }
}
