import AppKit
import SwiftUI

/// The menu of the running app: the panel over the aggregator's state.
struct MenuBarView: View {
    @ObservedObject var aggregator: StateAggregator
    @State private var isOpen = false

    var body: some View {
        PreferencesOpener { openPreferences in
            let input = aggregator.panelInput
            PanelView(
                state: { MenuModel.state(input, now: $0) },
                bar: MenuModel.bar(input),
                enabled: $aggregator.enabled,
                mode: $aggregator.mode,
                busy: aggregator.license.busy,
                perform: { perform($0, openPreferences: openPreferences) },
                openPreferences: openPreferences,
                quit: { NSApp.terminate(nil) }
            )
        }
        .environment(\.panelIsOpen, isOpen)
        .background(WindowVisibility(isVisible: $isOpen))
        .onAppear(perform: aggregator.refreshHelperStatus)
        .onChange(of: isOpen) { open in
            if open { aggregator.refreshHelperStatus() }
        }
    }

    private func perform(_ action: PanelAction, openPreferences: @escaping () -> Void) {
        let license = aggregator.license
        switch action {
        case .openLoginItems:
            aggregator.sleepFlag.openLoginItemsSettings()
        case .tryHelperAgain:
            aggregator.repairHelper()
        case .buy:
            NSWorkspace.shared.open(license.config.checkoutURL)
        case .enterKey:
            aggregator.preferencesTab = .license
            openPreferences()
        case .checkLicense:
            Task { @MainActor in
                await license.checkNow()
                showLicenseMessage(openPreferences)
            }
        case .activateAgain:
            guard let key = license.record.key else { return }
            Task { @MainActor in
                await license.activate(key: key)
                showLicenseMessage(openPreferences)
            }
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
        case .dismissSleepNote:
            aggregator.dismissSleepNote()
        case .openHelp:
            NSWorkspace.shared.open(AppLinks.help)
        }
    }

    /// The menu has no place for why a license action failed. Settings
    /// has, so it opens on the reason.
    @MainActor
    private func showLicenseMessage(_ openPreferences: () -> Void) {
        guard aggregator.license.message != nil else { return }
        aggregator.preferencesTab = .license
        openPreferences()
    }
}
