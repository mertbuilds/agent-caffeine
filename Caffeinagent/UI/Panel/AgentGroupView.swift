import SwiftUI

/// One agent: its header, and its sessions below it when the group is
/// open. A header with sessions below it is a button. The sessions are
/// always there, in a box that is as tall as the group is open.
struct AgentGroupView: View {
    let group: PanelGroup
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        let layout = Self.childLayout(of: group)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.children) { AgentChildView(child: $0, layout: layout) }
            }
            // The sessions take their new places at once when one comes,
            // goes or changes shape, so no text crosses another on its way.
            // The height of the group is what moves, and it cuts them.
            .transaction { $0.animation = nil }
            .reveal(isOpen: isOpen, height: Self.childrenHeight(of: group))
        }
    }

    private static func summaryPlace(_ group: PanelGroup) -> AgentRowView.SummaryPlace {
        if group.canToggle { return .whereItFits }
        return group.header.state == .idle ? .trailing : .below
    }

    /// From the widths of the texts at the width of the menu, so it is
    /// known before the layout and the layout never feeds it.
    static func childLayout(of group: PanelGroup) -> ChildLayout {
        ChildLayout.decide(group.children.compactMap(AgentChildView.widths), gap: PanelMetrics.childGap, available: PanelMetrics.childWidth)
    }

    /// For the height of the list before the layout.
    static func height(of group: PanelGroup, isOpen: Bool) -> CGFloat {
        AgentRowView.height(of: group.header, summary: summaryPlace(group)) + (isOpen ? childrenHeight(of: group) : 0)
    }

    /// Of the open sessions, with the room below the last one.
    static func childrenHeight(of group: PanelGroup) -> CGFloat {
        guard group.canToggle else { return 0 }
        let layout = childLayout(of: group)
        return group.children.reduce(PanelMetrics.childrenBottom) { $0 + AgentChildView.height(of: $1, layout: layout) }
    }
}
