import AppKit
import SwiftUI

/// The menu of the running app: the panel over the aggregator's state.
struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator
    @State private var isOpen = false
    @State private var panel = WindowVisibility.Holder()

    var body: some View {
        PreferencesOpener { openPreferences in
            let input = aggregator.panelInput
            PanelView(
                state: { MenuModel.state(input, now: $0) },
                bar: MenuModel.bar(input),
                enabled: $aggregator.enabled,
                mode: $aggregator.mode,
                perform: { perform($0, openPreferences: openPreferences) },
                openPreferences: openPreferences,
                quit: { NSApp.terminate(nil) }
            )
        }
        .environment(\.panelIsOpen, isOpen)
        .background(WindowVisibility(isVisible: $isOpen, holder: panel))
        .onAppear(perform: aggregator.refreshHelperStatus)
        .onChange(of: isOpen) { open in
            guard open else { return }
            aggregator.refreshHelperStatus()
            aggregator.refreshAgentHosts()
        }
    }

    private func perform(_ action: PanelAction, openPreferences: @escaping () -> Void) {
        switch action {
        case .openLoginItems:
            aggregator.sleepFlag.openLoginItemsSettings()
        case .tryHelperAgain:
            aggregator.repairHelper()
        case .setUpLidClosed:
            aggregator.preferencesTab = .lidClosed
            openPreferences()
        case .dismissLidClosedHint:
            aggregator.lidClosedHintDismissed = true
        case .pause(let choice):
            aggregator.startPause(choice)
        case .resume:
            aggregator.resumeNow()
        case .stayReachable(let choice):
            aggregator.startReachable(choice)
        case .stopReachable:
            aggregator.stopReachable()
        case .agentNotListed:
            aggregator.showsOtherTools = true
            aggregator.preferencesTab = .agents
            openPreferences()
        case .setAgentRule(let agentID, let rule):
            aggregator.setRule(rule, for: agentID)
        case .openAgentSettings:
            aggregator.preferencesTab = .agents
            openPreferences()
        case .goToAgent(let agent, _):
            if aggregator.goToAgent(agent) { panel.close() }
        case .stopHold(let id):
            aggregator.stopHold(id: id)
        case .stopJobHold(let id):
            aggregator.stopJobHold(id: id)
        case .dismissSleepNote:
            aggregator.dismissSleepNote()
        case .openHelp:
            NSWorkspace.shared.open(AppLinks.help)
        }
    }
}
