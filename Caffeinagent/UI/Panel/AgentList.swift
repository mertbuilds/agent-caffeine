import SwiftUI

/// The agents, or one friendly line when none is open. A long list scrolls.
struct AgentList: View {
    let rows: [PanelRow]
    let moreIdle: [PanelRow]
    let moreIdleTitle: String?
    let emptyText: String?
    @State private var isExpanded: Bool

    init(rows: [PanelRow], moreIdle: [PanelRow], moreIdleTitle: String?, emptyText: String?, startsExpanded: Bool = false) {
        self.rows = rows
        self.moreIdle = moreIdle
        self.moreIdleTitle = moreIdleTitle
        self.emptyText = emptyText
        _isExpanded = State(initialValue: startsExpanded)
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
        } else if contentHeight > PanelMetrics.listMaxHeight {
            ScrollView { list }
                .frame(height: PanelMetrics.listMaxHeight)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { AgentRowView(row: $0) }
            if let moreIdleTitle {
                MoreIdleRow(title: moreIdleTitle, isExpanded: $isExpanded)
                if isExpanded {
                    ForEach(moreIdle) { row in
                        AgentRowView(row: row)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        // The ring's slot reaches past the box, so the boxes stand on the gutter.
        .padding(.horizontal, PanelMetrics.gutter - PanelMetrics.ringGap)
        .padding(.vertical, 8)
        .clipped()
    }

    private var contentHeight: CGFloat {
        let shown = rows + (isExpanded ? moreIdle : [])
        let rowsHeight = shown.reduce(0) { $0 + ($1.state == .idle ? PanelMetrics.idleRowHeight : PanelMetrics.activeRowHeight) }
        return rowsHeight + (moreIdleTitle == nil ? 0 : PanelMetrics.idleRowHeight) + 16
    }
}
