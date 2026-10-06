import SwiftUI

/// The agents, or one friendly line when none is open. A long list scrolls.
struct AgentList: View {
    let groups: [PanelGroup]
    let moreIdle: [PanelGroup]
    let moreIdleTitle: String?
    let emptyText: String?
    @State private var isExpanded: Bool
    @State private var disclosure: GroupDisclosure
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        groups: [PanelGroup], moreIdle: [PanelGroup], moreIdleTitle: String?, emptyText: String?,
        startsExpanded: Bool = false, startsToggled: Set<String> = []
    ) {
        self.groups = groups
        self.moreIdle = moreIdle
        self.moreIdleTitle = moreIdleTitle
        self.emptyText = emptyText
        _isExpanded = State(initialValue: startsExpanded)
        var disclosure = GroupDisclosure()
        for group in groups + moreIdle where startsToggled.contains(group.id) { disclosure.toggle(group) }
        _disclosure = State(initialValue: disclosure)
    }

    var body: some View {
        if let emptyText {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, PanelMetrics.gutter + 8)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
        } else {
            // Always the same views, so a list that gets long changes
            // nothing but its height.
            ScrollView { list }
                .scrollDisabled(!scrolls)
                .frame(maxHeight: PanelMetrics.listMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { view(of: $0) }
            if let moreIdleTitle {
                MoreIdleRow(title: moreIdleTitle, isExpanded: $isExpanded)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(moreIdle) { view(of: $0) }
                }
                .reveal(isOpen: isExpanded, height: height(of: moreIdle))
            }
        }
        // The ring's slot reaches past the box, so the boxes stand on the gutter.
        .padding(.horizontal, PanelMetrics.gutter - PanelMetrics.ringGap)
        .padding(.vertical, 8)
        .clipped()
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: layouts)
        .onChange(of: kinds) { _ in disclosure = disclosure.settled(with: groups + moreIdle) }
    }

    private func view(of group: PanelGroup) -> some View {
        AgentGroupView(group: group, isOpen: disclosure.isOpen(group)) {
            withAnimation(reduceMotion ? nil : PanelMetrics.disclosure(opening: !disclosure.isOpen(group))) { disclosure.toggle(group) }
        }
    }

    private func height(of groups: [PanelGroup]) -> CGFloat {
        groups.reduce(0) { $0 + AgentGroupView.height(of: $1, isOpen: disclosure.isOpen($1)) }
    }

    /// The lines below a group move with its sessions when they change shape.
    private var layouts: [ChildLayout] {
        (groups + moreIdle).map(AgentGroupView.childLayout)
    }

    private var kinds: [String: PanelGroup.Kind] {
        Dictionary((groups + moreIdle).map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    /// Worked out before the layout, with the widths of the texts.
    private var scrolls: Bool {
        let groupsHeight = height(of: groups + (isExpanded ? moreIdle : []))
        return groupsHeight + (moreIdleTitle == nil ? 0 : PanelMetrics.idleRowHeight) + 16 > PanelMetrics.listMaxHeight
    }
}
