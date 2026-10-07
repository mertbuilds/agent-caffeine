import SwiftUI

/// One agent: its header, and its sessions below it when the group is
/// open. A header with sessions below it is a button. The sessions are
/// always there, in a box that is as tall as the group is open.
struct AgentGroupView: View {
    let group: PanelGroup
    let isOpen: Bool
    var perform: (PanelAction) -> Void = { _ in }
    let toggle: () -> Void

    var body: some View {
        let layout = Self.childLayout(of: group)
        VStack(alignment: .leading, spacing: 0) {
            Group {
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
                        .contentShape(Rectangle())
                }
            }
            .contextMenu { AgentRuleMenu(agentID: group.id, rule: group.rule, perform: perform) }
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

/// The menu of an agent's row: the rule of the agent, for an agent that
/// reads idle while it works, and the way to its settings. A rule that is
/// set has a check mark, and choosing it again takes it away.
struct AgentRuleMenu: View {
    let agentID: String
    let rule: AgentRule
    let perform: (PanelAction) -> Void

    var body: some View {
        ForEach([AgentRule.alwaysWorkingWhileOpen, .ignore], id: \.self) { choice in
            Toggle(PanelAction.setAgentRule(agentID: agentID, rule: choice).title, isOn: Binding(
                get: { rule == choice },
                set: { perform(.setAgentRule(agentID: agentID, rule: $0 ? choice : .automatic)) }
            ))
        }
        Divider()
        Button(PanelAction.openAgentSettings.title) { perform(.openAgentSettings) }
    }
}
