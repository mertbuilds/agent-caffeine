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
                        .goTo(group.header.goTo, radius: PanelMetrics.rowHoverRadius, perform: perform)
                }
            }
            .contextMenu { AgentRuleMenu(agentID: group.id, rule: group.rule, goTo: group.header.goTo, perform: perform) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.children) { child in
                    AgentChildView(child: child, layout: layout)
                        .goTo(child.goTo, radius: PanelMetrics.childHoverRadius, perform: perform)
                        .contextMenu {
                            if let goTo = child.goTo {
                                AgentRuleMenu(agentID: group.id, rule: group.rule, goTo: goTo, perform: perform)
                            }
                        }
                }
            }
            // The sessions take their new places at once when one comes,
            // goes or changes shape, so no text crosses another on its way.
            // The height of the group is what moves, and it cuts them.
            .transaction { $0.animation = nil }
            .revealWithRowHover(isOpen: isOpen, height: Self.childrenHeight(of: group))
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

/// The menu of an agent's row: the way to the app of a row that is one
/// session, the rule of the agent, for an agent that reads idle while it
/// works, and the way to its settings. A rule that is set has a check
/// mark, and choosing it again takes it away.
struct AgentRuleMenu: View {
    let agentID: String
    let rule: AgentRule
    var goTo: PanelAction?
    let perform: (PanelAction) -> Void

    var body: some View {
        if let goTo {
            Button(goTo.title) { perform(goTo) }
            Divider()
        }
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
