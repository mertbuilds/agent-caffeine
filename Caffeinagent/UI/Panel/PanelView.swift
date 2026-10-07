import SwiftUI

/// The menu, drawn from plain values so a preview needs no running app.
struct PanelView: View {
    /// What the menu shows at a moment. Asked again once a second while
    /// the menu is open, so the durations count on.
    let state: (Date) -> PanelState
    let bar: PanelBar
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

    var body: some View {
        VStack(spacing: 0) {
            // The clock stops above the bar. A tick that reached the bar
            // would close the submenu the user has open.
            PanelClock { now in
                PanelStateView(
                    state: state(now), busy: busy, startsExpanded: startsExpanded, startsToggled: startsToggled, perform: perform
                )
            }
            Divider()
            BottomBar(bar: bar, enabled: $enabled, mode: $mode, perform: perform, openPreferences: openPreferences, quit: quit)
                .equatable()
        }
        .frame(width: PanelMetrics.width)
        .tint(.brand)
    }
}

/// The part of the menu that follows the time and the agents: the glance
/// and the list.
private struct PanelStateView: View {
    let state: PanelState
    let busy: Bool
    let startsExpanded: Bool
    let startsToggled: Set<String>
    let perform: (PanelAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                VStack(spacing: PanelMetrics.batteryLineTop) {
                    HeroView(state: state)
                    if let battery = state.battery {
                        BatteryLine(battery: battery)
                            .transition(.opacity)
                    }
                }
                if let sleepNote = state.sleepNote {
                    AttentionLine(attention: sleepNote, perform: perform)
                        .transition(.opacity)
                }
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
                emptyText: state.emptyText, emptyAction: state.emptyAction,
                startsExpanded: startsExpanded, startsToggled: startsToggled, perform: perform
            )
        }
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.attention)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.sleepNote)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.battery == nil)
        .animation(reduceMotion ? nil : PanelMetrics.stateChange, value: state.groups.map { [$0.id] + $0.children.map(\.id) })
    }
}
