import SwiftUI

/// The menu, drawn from plain values so a preview needs no running app.
struct PanelView: View {
    let state: PanelState
    @Binding var enabled: Bool
    @Binding var mode: AwakeMode
    /// A license check is under way.
    var busy = false
    var startsExpanded = false
    /// Groups that start the other way round than their kind says.
    var startsToggled: Set<String> = []
    let perform: (PanelAction) -> Void
    let openPreferences: () -> Void
    let quit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HeroView(state: state)
                if let attention = state.attention {
                    AttentionLine(attention: attention, busy: busy, perform: perform)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, PanelMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
            Divider()
            AgentList(
                groups: state.groups, moreIdle: state.moreIdle, moreIdleTitle: state.moreIdleTitle,
                emptyText: state.emptyText, startsExpanded: startsExpanded, startsToggled: startsToggled
            )
            Divider()
            BottomBar(
                enabled: $enabled, mode: $mode, licenseActions: state.licenseActions,
                perform: perform, openPreferences: openPreferences, quit: quit
            )
        }
        .frame(width: PanelMetrics.width)
        .tint(.brand)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.attention)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.groups.map { [$0.id] + $0.children.map(\.id) })
    }
}
