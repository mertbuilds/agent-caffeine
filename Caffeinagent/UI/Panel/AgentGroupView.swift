import SwiftUI

/// One agent: its header, and its sessions below it when the group is
/// open. A header with sessions below it is a button.
struct AgentGroupView: View {
    let group: PanelGroup
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.canToggle {
                Button(action: toggle) {
                    AgentRowView(row: group.header, summary: Self.summaryPlace(group), isOpen: isOpen)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.accessibilityLabel)
                .accessibilityValue(isOpen ? PanelText.expanded : PanelText.collapsed)
            } else {
                AgentRowView(row: group.header, summary: Self.summaryPlace(group))
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.children) { AgentChildView(child: $0) }
                }
                .padding(.bottom, PanelMetrics.childrenBottom)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private static func summaryPlace(_ group: PanelGroup) -> AgentRowView.SummaryPlace {
        if group.canToggle { return .whereItFits }
        return group.header.state == .idle ? .trailing : .below
    }

    /// For the height of the list before the layout.
    static func height(of group: PanelGroup, isOpen: Bool) -> CGFloat {
        let header = AgentRowView.height(of: group.header, summary: summaryPlace(group))
        guard isOpen else { return header }
        return group.children.reduce(header + PanelMetrics.childrenBottom) { $0 + AgentChildView.height(of: $1) }
    }
}
